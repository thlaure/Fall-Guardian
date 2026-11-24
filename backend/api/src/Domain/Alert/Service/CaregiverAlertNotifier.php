<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

use App\Domain\Alert\Port\PushAttemptRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\PermanentPushDeliveryException;
use App\Domain\Push\Exception\PushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverPushToken;
use App\Entity\FallAlert;
use App\Entity\PushAttempt;
use App\Shared\DateTime\ApiDateTimeFormatter;
use Psr\Log\LoggerInterface;
use Throwable;

/**
 * Sends one notification round for a fall alert to every linked caregiver.
 *
 * Each push attempt is persisted as soon as it completes, and caregivers that
 * already received this round's push are skipped, so a round interrupted by a
 * crash can be resumed without duplicate notifications.
 */
final readonly class CaregiverAlertNotifier
{
    public function __construct(
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private CaregiverPushTokenRepositoryInterface $pushTokenRepository,
        private PushAttemptRepositoryInterface $pushAttemptRepository,
        private PushGatewayInterface $pushGateway,
        private LoggerInterface $logger,
    ) {
    }

    /**
     * @param int                     $reminderNumber   0 for the initial alert push, N for the N-th reminder
     * @param (callable(): void)|null $afterEachAttempt invoked after every provider call (e.g. to refresh a claim)
     */
    public function notify(FallAlert $alert, int $reminderNumber, ?callable $afterEachAttempt = null): NotificationRoundResult
    {
        $alertId = $alert->getId()->toRfc4122();
        $links = $this->caregiverLinkRepository->findActiveByProtectedDevice($alert->getDevice());
        $alreadySentIds = array_flip($this->pushAttemptRepository->findSentCaregiverDeviceIds($alert, $reminderNumber));
        $provider = $this->pushGateway->getProviderName();
        $fallTimestamp = ApiDateTimeFormatter::formatUtc($alert->getFallDetectedAt());
        $cancelDeadlineAt = ApiDateTimeFormatter::formatUtc($alert->getCancelDeadlineAt());

        $seen = [];
        $alreadySent = 0;
        $sent = 0;
        $transientFailures = 0;
        $invalidTokens = 0;
        $missingTokens = 0;
        $permanentFailures = 0;

        foreach ($links as $link) {
            $caregiverDevice = $link->getCaregiverDevice();
            $caregiverId = $caregiverDevice->getId()->toRfc4122();

            if (isset($seen[$caregiverId])) {
                continue;
            }

            $seen[$caregiverId] = true;

            if (isset($alreadySentIds[$caregiverId])) {
                ++$alreadySent;

                continue;
            }

            $pushToken = $this->pushTokenRepository->findByDevice($caregiverDevice);

            if (!$pushToken instanceof CaregiverPushToken) {
                ++$missingTokens;

                continue;
            }

            $attempt = new PushAttempt($alert, $caregiverDevice, $provider, $reminderNumber);
            $payload = new FallAlertPushPayload(
                $alertId,
                $fallTimestamp,
                $cancelDeadlineAt,
                $alert->getLatitude(),
                $alert->getLongitude(),
                $link->getProtectedPersonName(),
                $reminderNumber > 0,
            );

            try {
                $result = $this->pushGateway->send($pushToken->getFcmToken(), $payload);
                $attempt->markSent($result['providerMessageId']);
                ++$sent;
            } catch (InvalidPushTokenException $exception) {
                $attempt->markFailed($exception->getReason(), $exception->getMessage());
                ++$invalidTokens;
                $removed = $this->pushTokenRepository->deleteIfUnchanged($caregiverDevice, $pushToken->getFcmToken());
                $this->logger->warning('push.token_invalid', [
                    'alertId' => $alertId,
                    'caregiverDeviceId' => $caregiverDevice->getPublicId(),
                    'reason' => $exception->getReason(),
                    'tokenRemoved' => $removed,
                ]);
            } catch (PermanentPushDeliveryException $exception) {
                // The message was rejected, not the token: keep the token.
                $attempt->markFailed($exception->getReason(), $exception->getMessage());
                ++$permanentFailures;
                $this->logger->error('push.delivery_rejected', [
                    'alertId' => $alertId,
                    'caregiverDeviceId' => $caregiverDevice->getPublicId(),
                    'reason' => $exception->getReason(),
                ]);
            } catch (Throwable $exception) {
                $reason = $exception instanceof PushDeliveryException ? $exception->getReason() : 'unexpected';
                $attempt->markFailed($reason, $exception instanceof PushDeliveryException ? $exception->getMessage() : 'Unexpected push delivery error.');
                ++$transientFailures;
                $this->logger->warning('push.delivery_failed', [
                    'alertId' => $alertId,
                    'caregiverDeviceId' => $caregiverDevice->getPublicId(),
                    'reason' => $reason,
                    'exceptionClass' => $exception::class,
                ]);
            }

            $this->pushAttemptRepository->save($attempt);

            if (null !== $afterEachAttempt) {
                $afterEachAttempt();
            }
        }

        return new NotificationRoundResult(count($seen), $alreadySent, $sent, $transientFailures, $invalidTokens, $missingTokens, $permanentFailures);
    }
}
