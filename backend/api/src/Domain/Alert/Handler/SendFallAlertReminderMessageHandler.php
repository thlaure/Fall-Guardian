<?php

declare(strict_types=1);

namespace App\Domain\Alert\Handler;

use App\Domain\Alert\Message\SendFallAlertReminderMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\CaregiverAlertNotifier;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

/**
 * Re-notifies linked caregivers about an alert nobody acknowledged yet. The
 * reminder number was reserved atomically by the reconciler; caregivers who
 * already got this reminder (redelivered message) are skipped.
 */
#[AsMessageHandler]
final readonly class SendFallAlertReminderMessageHandler
{
    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private CaregiverAlertNotifier $notifier,
        private LoggerInterface $logger,
    ) {
    }

    public function __invoke(SendFallAlertReminderMessage $message): void
    {
        $alert = $this->fallAlertRepository->findById($message->fallAlertId);

        if (!$alert instanceof FallAlert) {
            return;
        }

        if (in_array($alert->getStatus(), [FallAlertStatus::Dispatching, FallAlertStatus::Failed], true)) {
            // A dispatch retry round is running or scheduled: defer instead of
            // consuming the reminder; the reconciler reserves it again once the
            // alert is sent/partially sent.
            $released = $this->fallAlertRepository->releaseReminder($message->fallAlertId, $message->reminderNumber);
            $this->logger->info('alert.reminder_deferred', [
                'alertId' => $message->fallAlertId,
                'reminder' => $message->reminderNumber,
                'status' => $alert->getStatus()->value,
                'released' => $released,
            ]);

            return;
        }

        if (!in_array($alert->getStatus(), [FallAlertStatus::Sent, FallAlertStatus::PartiallySent], true)) {
            $this->logger->info('alert.reminder_skipped', [
                'alertId' => $message->fallAlertId,
                'reminder' => $message->reminderNumber,
                'status' => $alert->getStatus()->value,
            ]);

            return;
        }

        $result = $this->notifier->notify($alert, $message->reminderNumber);

        $this->logger->info('alert.reminder_sent', [
            'alertId' => $message->fallAlertId,
            'reminder' => $message->reminderNumber,
            ...$result->toLogContext(),
        ]);
    }
}
