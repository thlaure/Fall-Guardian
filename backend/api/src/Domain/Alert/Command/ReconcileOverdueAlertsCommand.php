<?php

declare(strict_types=1);

namespace App\Domain\Alert\Command;

use App\Domain\Alert\Service\OverdueAlertReconciler;
use App\Domain\Retention\Service\DataRetentionService;
use Override;
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

#[AsCommand(
    name: 'app:alerts:reconcile-overdue',
    description: 'Queues overdue, interrupted or retryable fall-alert dispatches and unacknowledged-alert reminders from database state.',
)]
final class ReconcileOverdueAlertsCommand extends Command
{
    private const int DEFAULT_RETENTION_INTERVAL_SECONDS = 3600;

    public function __construct(
        private readonly OverdueAlertReconciler $reconciler,
        private readonly DataRetentionService $retentionService,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    #[Override]
    protected function configure(): void
    {
        $this
            ->addOption('watch', null, InputOption::VALUE_NONE, 'Continuously reconcile once per second.')
            ->addOption(
                'retention-interval',
                null,
                InputOption::VALUE_REQUIRED,
                'In watch mode, run the data-retention purge every N seconds (0 disables it).',
                (string) self::DEFAULT_RETENTION_INTERVAL_SECONDS,
            );
    }

    #[Override]
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $watch = true === $input->getOption('watch');
        $rawInterval = $input->getOption('retention-interval');
        $retentionInterval = is_numeric($rawInterval) ? max(0, (int) $rawInterval) : self::DEFAULT_RETENTION_INTERVAL_SECONDS;
        $lastRetentionRunAt = 0;

        do {
            $reconciled = $this->reconciler->reconcile();

            if ($reconciled > 0) {
                $output->writeln(sprintf('Queued %d overdue alert dispatch(es) or reminder(s).', $reconciled));
            }

            if ($watch && $retentionInterval > 0 && time() - $lastRetentionRunAt >= $retentionInterval) {
                $lastRetentionRunAt = time();
                $this->runRetention();
            }

            if ($watch) {
                sleep(1);
            }
        } while ($watch);

        return Command::SUCCESS;
    }

    private function runRetention(): void
    {
        try {
            $this->retentionService->purge();
        } catch (Throwable $exception) {
            // Retention is housekeeping: it must never stop alert escalation.
            $this->logger->error('retention.failed', ['exceptionClass' => $exception::class]);
        }
    }
}
