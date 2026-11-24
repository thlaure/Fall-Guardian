<?php

declare(strict_types=1);

namespace App\Domain\Retention\Service;

use App\Domain\Retention\Port\RetentionRepositoryInterface;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;

/**
 * Applies the data-retention policy (GDPR storage limitation):
 *  - closed fall alerts, with push attempts and acknowledgements, are deleted
 *    after `alertRetentionDays`;
 *  - coordinates of closed alerts are erased after `locationRetentionDays`;
 *  - used/expired invites and companion enrollments are deleted after 7 days;
 *  - rate-limit buckets are deleted one day after their window started.
 */
final readonly class DataRetentionService
{
    public const int SHORT_LIVED_RETENTION_DAYS = 7;

    public const int RATE_LIMIT_RETENTION_HOURS = 24;

    private const int BATCH_SIZE = 500;

    /** Upper bound of batches per category and run, to keep one run short. */
    private const int MAX_BATCHES = 200;

    public function __construct(
        private RetentionRepositoryInterface $retentionRepository,
        private ClockInterface $clock,
        private LoggerInterface $logger,
        private int $alertRetentionDays,
        private int $locationRetentionDays,
    ) {
    }

    /** @return array{deletedAlerts: int, erasedLocations: int, deletedInvites: int, deletedEnrollments: int, deletedRateLimitBuckets: int} */
    public function purge(): array
    {
        $now = $this->clock->now();
        $alertCutoff = $now->modify(sprintf('-%d days', max(1, $this->alertRetentionDays)));
        $locationCutoff = $now->modify(sprintf('-%d days', max(1, min($this->locationRetentionDays, $this->alertRetentionDays))));
        $shortLivedCutoff = $now->modify(sprintf('-%d days', self::SHORT_LIVED_RETENTION_DAYS));
        $rateLimitCutoff = $now->modify(sprintf('-%d hours', self::RATE_LIMIT_RETENTION_HOURS));

        $result = [
            'deletedAlerts' => $this->drain(fn (int $batch): int => $this->retentionRepository->deleteClosedAlertsBefore($alertCutoff, $batch)),
            'erasedLocations' => $this->drain(fn (int $batch): int => $this->retentionRepository->eraseLocationOfClosedAlertsBefore($locationCutoff, $batch)),
            'deletedInvites' => $this->drain(fn (int $batch): int => $this->retentionRepository->deleteFinishedInvitesBefore($shortLivedCutoff, $batch)),
            'deletedEnrollments' => $this->drain(fn (int $batch): int => $this->retentionRepository->deleteFinishedCompanionEnrollmentsBefore($shortLivedCutoff, $batch)),
            'deletedRateLimitBuckets' => $this->drain(fn (int $batch): int => $this->retentionRepository->deleteRateLimitBucketsBefore($rateLimitCutoff, $batch)),
        ];

        $this->logger->info('retention.purged', $result);

        return $result;
    }

    /** @param callable(int): int $step */
    private function drain(callable $step): int
    {
        $total = 0;

        for ($batches = 0; $batches < self::MAX_BATCHES; ++$batches) {
            $affected = $step(self::BATCH_SIZE);
            $total += $affected;

            if ($affected < self::BATCH_SIZE) {
                break;
            }
        }

        return $total;
    }
}
