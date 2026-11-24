<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;

interface FallAlertRepositoryInterface
{
    public function findOneByDeviceAndClientAlertId(Device $device, string $clientAlertId): ?FallAlert;

    public function findById(string $id): ?FallAlert;

    public function claimForDispatch(string $id, DateTimeImmutable $now, DateTimeImmutable $staleBefore): ?FallAlert;

    public function cancelPending(Device $device, string $clientAlertId, DateTimeImmutable $now): ?FallAlert;

    /** @return list<string> */
    public function findDispatchCandidateIds(DateTimeImmutable $now, DateTimeImmutable $staleBefore, int $limit = 100): array;

    /**
     * Refreshes the dispatch claim timestamp while a dispatch round is still
     * running, so slow provider calls are not mistaken for a crashed worker.
     */
    public function touchDispatchClaim(string $id, DateTimeImmutable $now): void;

    /**
     * Records the outcome of a dispatch round, but only if the alert is still
     * `dispatching`: an acknowledgement or other transition that happened
     * meanwhile must never be overwritten.
     *
     * @return bool true when the outcome was applied
     */
    public function completeDispatch(string $id, FallAlertStatus $status, ?DateTimeImmutable $nextRetryAt): bool;

    /**
     * Sent/partially-sent alerts whose acknowledgement deadline passed and
     * that may receive another reminder.
     *
     * @return list<array{id: string, reminderCount: int}>
     */
    public function findReminderCandidates(DateTimeImmutable $now, DateTimeImmutable $lastReminderBefore, int $maxReminders, int $limit = 100): array;

    /**
     * Atomically reserves reminder number `$expectedReminderCount + 1`. Returns
     * false when another reconciler run already reserved it or the alert was
     * acknowledged/cancelled meanwhile.
     */
    public function claimReminder(string $id, int $expectedReminderCount, DateTimeImmutable $now): bool;

    /**
     * Earliest moment an escalation became due without having completed:
     * received alerts past their cancel deadline, dispatching alerts (claim
     * time), and retryable alerts past their retry time.
     */
    public function findOldestPendingEscalationDueAt(DateTimeImmutable $now): ?DateTimeImmutable;

    /** @return list<FallAlert> */
    public function findByDevice(Device $device, int $limit = 50): array;

    public function save(FallAlert $alert): void;
}
