<?php

declare(strict_types=1);

namespace App\Domain\Retention\Command;

use App\Domain\Retention\Service\DataRetentionService;
use Override;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'app:retention:purge',
    description: 'Deletes or anonymises data past its retention period (closed alerts, locations, invites, enrollments, rate-limit buckets).',
)]
final class PurgeExpiredDataCommand extends Command
{
    public function __construct(private readonly DataRetentionService $retentionService)
    {
        parent::__construct();
    }

    #[Override]
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        foreach ($this->retentionService->purge() as $metric => $count) {
            $output->writeln(sprintf('%s: %d', $metric, $count));
        }

        return Command::SUCCESS;
    }
}
