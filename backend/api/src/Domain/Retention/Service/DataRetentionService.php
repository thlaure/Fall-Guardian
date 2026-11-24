<?php

declare(strict_types=1);

namespace App\Domain\Retention\Service;

use App\Domain\Retention\Port\RetentionRepositoryInterface;
use Closure;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;

/**
 * Applies the data-retention policy (GDPR storage limitation):
 *  - closed fall alerts, with push attempts and acknowledgements, are deleted
 *    after `alertRetentionDays`;
 *  - coordinates of closed alerts are erased after `locationRetentionDays`;
 *  - used/expired invites and companion enrollments are deleted after 7 days;
 *  - rate-limit buckets are deleted one day after their window started;
 *  - heartbeats of workers silent for a day (replaced containers) are deleted.
 */
final readonly class DataRetentionService
{
    public const int SHORT_LIVED_RETENTION_DAYS = 7;

    public const int RATE_LIMIT_RETENTION_HOURS = 24;

    private const int BATCH_SIZE = 500;

    /** Upper bound of batches per category and run, to keep one run short. */
    private const int MAX_BATCHES = 200;

    /** @var Closure(): float */
    private Closure $monotonicSeconds;

    /** @param (Closure(): float)|null $monotonicSeconds monotonic clock in seconds, injectable for tests */
    public function __construct(
        private RetentionRepositoryInterface $retentionRepository,
        private ClockInterface $clock,
        private LoggerInterface $logger,
        private int $alertRetentionDays,
        private int $locationRetentionDays,
        ?Closure $monotonicSeconds = null,
    ) {
        $this->monotonicSeconds = $monotonicSeconds ?? static fn (): float => hrtime(true) / 1e9;
    }

    /**
     * @param float|null $timeBudgetSeconds stop starting new batches once this much time has been spent;
     *                                      the remaining work is picked up by the next run
     *
     * @return array{deletedRateLimitBuckets: int, deletedHeartbeats: int, deletedInvites: int, deletedEnrollments: int, erasedLocations: int, deletedAlerts: int, completed: bool}
     */
    public function purge(?float $timeBudgetSeconds = null): array
    {
        $deadline = null === $timeBudgetSeconds ? null : ($this->monotonicSeconds)() + $timeBudgetSeconds;
        $now = $this->clock->now();
        $alertCutoff = $now->modify(sprintf('-%d days', max(1, $this->alertRetentionDays)));
        $locationCutoff = $now->modify(sprintf('-%d days', max(1, min($this->locationRetentionDays, $this->alertRetentionDays))));
        $shortLivedCutoff = $now->modify(sprintf('-%d days', self::SHORT_LIVED_RETENTION_DAYS));
        $rateLimitCutoff = $now->modify(sprintf('-%d hours', self::RATE_LIMIT_RETENTION_HOURS));

        // Cheap categories first, so a large alert backlog never starves them.
        $steps = [
            'deletedRateLimitBuckets' => fn (int $batch): int => $this->retentionRepository->deleteRateLimitBucketsBefore($rateLimitCutoff, $batch),
            'deletedHeartbeats' => fn (int $batch): int => $this->retentionRepository->deleteHeartbeatsBefore($rateLimitCutoff, $batch),
            'deletedInvites' => fn (int $batch): int => $this->retentionRepository->deleteFinishedInvitesBefore($shortLivedCutoff, $batch),
            'deletedEnrollments' => fn (int $batch): int => $this->retentionRepository->deleteFinishedCompanionEnrollmentsBefore($shortLivedCutoff, $batch),
            'erasedLocations' => fn (int $batch): int => $this->retentionRepository->eraseLocationOfClosedAlertsBefore($locationCutoff, $batch),
            'deletedAlerts' => fn (int $batch): int => $this->retentionRepository->deleteClosedAlertsBefore($alertCutoff, $batch),
        ];

        $result = ['completed' => true];

        foreach ($steps as $metric => $step) {
            [$result[$metric], $drained] = $this->drain($step, $deadline);
            $result['completed'] = $result['completed'] && $drained;
        }

        /* @var array{deletedRateLimitBuckets: int, deletedHeartbeats: int, deletedInvites: int, deletedEnrollments: int, erasedLocations: int, deletedAlerts: int, completed: bool} $result */
        $this->logger->info('retention.purged', $result);

        return $result;
    }

    /**
     * @param callable(int): int $step
     *
     * @return array{0: int, 1: bool} affected rows, and whether the category is fully drained
     */
    private function drain(callable $step, ?float $deadline): array
    {
        $total = 0;

        for ($batches = 0; $batches < self::MAX_BATCHES; ++$batches) {
            if (null !== $deadline && ($this->monotonicSeconds)() >= $deadline) {
                return [$total, false];
            }

            $affected = $step(self::BATCH_SIZE);
            $total += $affected;

            if ($affected < self::BATCH_SIZE) {
                return [$total, true];
            }
        }

        return [$total, false];
    }
}
