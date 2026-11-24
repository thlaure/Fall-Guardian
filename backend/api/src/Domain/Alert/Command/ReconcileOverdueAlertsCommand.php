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

    /** Retention never runs right at start-up, when escalation catch-up matters most. */
    private const int DEFAULT_RETENTION_FIRST_DELAY_SECONDS = 600;

    /** Upper bound of one retention run inside the loop; unfinished work resumes later. */
    public const float RETENTION_TIME_BUDGET_SECONDS = 2.0;

    /** When a run hit its time budget, continue after this delay instead of the full interval. */
    private const int RETENTION_CATCH_UP_DELAY_SECONDS = 60;

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
            )
            ->addOption(
                'retention-first-delay',
                null,
                InputOption::VALUE_REQUIRED,
                'In watch mode, wait N seconds after start-up before the first retention run.',
                (string) self::DEFAULT_RETENTION_FIRST_DELAY_SECONDS,
            );
    }

    #[Override]
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $watch = true === $input->getOption('watch');
        $rawInterval = $input->getOption('retention-interval');
        $retentionInterval = is_numeric($rawInterval) ? max(0, (int) $rawInterval) : self::DEFAULT_RETENTION_INTERVAL_SECONDS;
        $rawFirstDelay = $input->getOption('retention-first-delay');
        $firstDelay = is_numeric($rawFirstDelay) ? max(0, (int) $rawFirstDelay) : self::DEFAULT_RETENTION_FIRST_DELAY_SECONDS;
        $nextRetentionAt = time() + $firstDelay;

        do {
            $reconciled = $this->reconciler->reconcile();

            if ($reconciled > 0) {
                $output->writeln(sprintf('Queued %d overdue alert dispatch(es) or reminder(s).', $reconciled));
            }

            if ($watch && $retentionInterval > 0 && time() >= $nextRetentionAt) {
                $completed = $this->runRetention();
                $nextRetentionAt = time() + ($completed ? $retentionInterval : min($retentionInterval, self::RETENTION_CATCH_UP_DELAY_SECONDS));
            }

            if ($watch) {
                sleep(1);
            }
        } while ($watch);

        return Command::SUCCESS;
    }

    /**
     * Runs one time-boxed retention pass between two reconcile iterations, so
     * escalation is delayed by at most the time budget plus one batch.
     *
     * @return bool whether all retention work was done
     */
    private function runRetention(): bool
    {
        try {
            return $this->retentionService->purge(self::RETENTION_TIME_BUDGET_SECONDS)['completed'];
        } catch (Throwable $exception) {
            // Retention is housekeeping: it must never stop alert escalation.
            $this->logger->error('retention.failed', ['exceptionClass' => $exception::class]);

            return true;
        }
    }
}
