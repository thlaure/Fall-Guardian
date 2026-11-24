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

        foreach ($candidates as $candidate) {
            // The conditional reservation makes reminders idempotent across
            // concurrent or restarted reconcilers: each number is queued once.
            if (!$this->fallAlertRepository->claimReminder($candidate['id'], $candidate['reminderCount'], $now)) {
                continue;
            }

            $reminderNumber = $candidate['reminderCount'] + 1;
            $this->messageBus->dispatch(new SendFallAlertReminderMessage($candidate['id'], $reminderNumber));
            $this->logger->info('alert.reminder_queued', [
                'alertId' => $candidate['id'],
                'reminder' => $reminderNumber,
            ]);
            ++$queued;
        }

        return $queued;
    }
}
