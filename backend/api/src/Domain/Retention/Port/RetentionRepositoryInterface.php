<?php

declare(strict_types=1);

namespace App\Domain\Retention\Port;

use DateTimeImmutable;

interface RetentionRepositoryInterface
{
    /**
     * Deletes up to `$batchSize` closed fall alerts received before `$cutoff`,
     * with their push attempts and acknowledgements.
     *
     * @return int number of deleted alerts
     */
    public function deleteClosedAlertsBefore(DateTimeImmutable $cutoff, int $batchSize): int;

    /** @return int number of alerts whose coordinates were erased */
    public function eraseLocationOfClosedAlertsBefore(DateTimeImmutable $cutoff, int $batchSize): int;

    /** @return int number of used or expired invites deleted */
    public function deleteFinishedInvitesBefore(DateTimeImmutable $cutoff, int $batchSize): int;

    /** @return int number of claimed or expired companion enrollments deleted */
    public function deleteFinishedCompanionEnrollmentsBefore(DateTimeImmutable $cutoff, int $batchSize): int;

    /** @return int number of rate-limit buckets whose window started before the cutoff */
    public function deleteRateLimitBucketsBefore(DateTimeImmutable $cutoff, int $batchSize): int;

    /** @return int number of heartbeats of workers gone for good (e.g. replaced containers) */
    public function deleteHeartbeatsBefore(DateTimeImmutable $cutoff, int $batchSize): int;
}
