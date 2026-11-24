<?php

declare(strict_types=1);

namespace App\Domain\Healthcheck\Command;

use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use Override;
use Psr\Clock\ClockInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

/**
 * Container healthcheck for background processes without an HTTP port:
 * exits non-zero when the component's heartbeat is missing or too old.
 */
#[AsCommand(
    name: 'app:health:heartbeat',
    description: 'Exits with status 1 when a background component heartbeat is missing or stale.',
)]
final class HeartbeatCheckCommand extends Command
{
    private const array COMPONENTS = [HeartbeatRepositoryInterface::RECONCILER, HeartbeatRepositoryInterface::MESSENGER];

    public function __construct(
        private readonly HeartbeatRepositoryInterface $heartbeatRepository,
        private readonly ClockInterface $clock,
    ) {
        parent::__construct();
    }

    #[Override]
    protected function configure(): void
    {
        $this
            ->addArgument('component', InputArgument::REQUIRED, sprintf('One of: %s.', implode(', ', self::COMPONENTS)))
            ->addOption('max-age', null, InputOption::VALUE_REQUIRED, 'Maximum heartbeat age in seconds.', '120');
    }

    #[Override]
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $component = $input->getArgument('component');
        $rawMaxAge = $input->getOption('max-age');

        if (!is_string($component) || !in_array($component, self::COMPONENTS, true) || !is_numeric($rawMaxAge)) {
            $output->writeln('Invalid component or max-age.');

            return Command::INVALID;
        }

        try {
            $lastBeatAt = $this->heartbeatRepository->lastBeatAt($component);
            $now = $this->clock->now();
        } catch (Throwable) {
            $output->writeln('Database unavailable.');

            return Command::FAILURE;
        }

        if (null === $lastBeatAt) {
            $output->writeln(sprintf('No heartbeat recorded for %s.', $component));

            return Command::FAILURE;
        }

        $age = $now->getTimestamp() - $lastBeatAt->getTimestamp();

        if ($age > (int) $rawMaxAge) {
            $output->writeln(sprintf('%s heartbeat is %d seconds old.', $component, $age));

            return Command::FAILURE;
        }

        $output->writeln(sprintf('%s heartbeat is %d seconds old.', $component, $age));

        return Command::SUCCESS;
    }
}
