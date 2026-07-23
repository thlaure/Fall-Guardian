<?php

declare(strict_types=1);

namespace App\Domain\Alert\Command;

use App\Domain\Alert\Service\OverdueAlertReconciler;
use Override;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'app:alerts:reconcile-overdue',
    description: 'Queues overdue or interrupted fall-alert dispatches from database state.',
)]
final class ReconcileOverdueAlertsCommand extends Command
{
    public function __construct(private readonly OverdueAlertReconciler $reconciler)
    {
        parent::__construct();
    }

    #[Override]
    protected function configure(): void
    {
        $this->addOption('watch', null, InputOption::VALUE_NONE, 'Continuously reconcile once per second.');
    }

    #[Override]
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $watch = true === $input->getOption('watch');

        do {
            $reconciled = $this->reconciler->reconcile();

            if ($reconciled > 0) {
                $output->writeln(sprintf('Queued %d overdue alert(s).', $reconciled));
            }

            if ($watch) {
                sleep(1);
            }
        } while ($watch);

        return Command::SUCCESS;
    }
}
