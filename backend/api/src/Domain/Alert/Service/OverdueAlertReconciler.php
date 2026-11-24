<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

use App\Domain\Alert\Handler\SendFallAlertPushMessageHandler;
use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Message\SendFallAlertReminderMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use App\Entity\FallAlert;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Throwable;

/**
 * Database-driven safety net for alert escalation. Every run:
 *  - queues alerts whose grace period expired, whose dispatch was interrupted,
 *    or whose failed/partial dispatch is due for a retry;
 *  - reserves and queues reminders for delivered alerts nobody acknowledged;
 *  - records a heartbeat used by the readiness check.
 */
final readonly class OverdueAlertReconciler
{
    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private MessageBusInterface $messageBus,
        private ClockInterface $clock,
        private HeartbeatRepositoryInterface $heartbeatRepository,
        private LoggerInterface $logger,
    ) {
    }

    /** @return int number of queued dispatch rounds and reminders */
    public function reconcile(int $limit = 100): int
    {
        $now = $this->clock->now();
        $staleBefore = $now->modify(sprintf('-%d seconds', SendFallAlertPushMessageHandler::STALE_DISPATCH_CLAIM_SECONDS));
        $alertIds = $this->fallAlertRepository->findDispatchCandidateIds($now, $staleBefore, $limit);

        foreach ($alertIds as $alertId) {
            $this->messageBus->dispatch(new SendFallAlertPushMessage($alertId));
        }

        $queued = count($alertIds) + $this->queueReminders($limit);
        $this->heartbeatRepository->beat(HeartbeatRepositoryInterface::RECONCILER, $now);

        return $queued;
    }

    private function queueReminders(int $limit): int
    {
        $now = $this->clock->now();
        $candidates = $this->fallAlertRepository->findReminderCandidates(
            $now,
            $now->modify(sprintf('-%d seconds', FallAlert::REMINDER_SPACING_SECONDS)),
            FallAlert::MAX_REMINDERS,
            $limit,
        );
        $queued = 0;

        // Outbox recovery first: reserved numbers whose enqueue never succeeded.
        foreach ($this->fallAlertRepository->findPendingReminders(
            $now->modify(sprintf('-%d seconds', FallAlert::REMINDER_ENQUEUE_RETRY_SECONDS)),
            $limit,
        ) as $pending) {
            if ($this->enqueueReminder($pending['id'], $pending['reminderNumber'], true)) {
                ++$queued;
            }
        }

        foreach ($candidates as $candidate) {
            // The conditional reservation makes reminders idempotent across
            // concurrent or restarted reconcilers: each number is reserved once.
            if (!$this->fallAlertRepository->claimReminder($candidate['id'], $candidate['reminderCount'], $now)) {
                continue;
            }

            if ($this->enqueueReminder($candidate['id'], $candidate['reminderCount'] + 1, false)) {
                ++$queued;
            }
        }

        return $queued;
    }

    /**
     * Hands a reserved reminder to the queue and confirms it. If the queue is
     * unavailable the reservation stays pending and the same number is
     * enqueued again by a later run; escalation of other alerts continues.
     */
    private function enqueueReminder(string $alertId, int $reminderNumber, bool $recovered): bool
    {
        try {
            $this->messageBus->dispatch(new SendFallAlertReminderMessage($alertId, $reminderNumber));
        } catch (Throwable $exception) {
            $this->logger->error('alert.reminder_enqueue_failed', [
                'alertId' => $alertId,
                'reminder' => $reminderNumber,
                'exceptionClass' => $exception::class,
            ]);

            return false;
        }

        $this->fallAlertRepository->markReminderEnqueued($alertId, $reminderNumber);
        $this->logger->info('alert.reminder_queued', [
            'alertId' => $alertId,
            'reminder' => $reminderNumber,
            'recovered' => $recovered,
        ]);

        return true;
    }
}
