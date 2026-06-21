<?php

declare(strict_types=1);

namespace App\Domain\Alert\Handler;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverPushToken;
use App\Entity\FallAlert;
use App\Entity\PushAttempt;
use App\Shared\DateTime\ApiDateTimeFormatter;
use DateTimeImmutable;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Throwable;

#[AsMessageHandler]
final readonly class SendFallAlertPushMessageHandler
{
    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private CaregiverPushTokenRepositoryInterface $pushTokenRepository,
        private PushGatewayInterface $pushGateway,
    ) {
    }

    public function __invoke(SendFallAlertPushMessage $message): void
    {
        $alert = $this->fallAlertRepository->findById($message->fallAlertId);

        if (!$alert instanceof FallAlert || $alert->getCancelledAt() instanceof DateTimeImmutable) {
            return;
        }

        $links = $this->caregiverLinkRepository->findActiveByProtectedDevice($alert->getDevice());

        if ([] === $links) {
            return;
        }

        $fallTimestamp = ApiDateTimeFormatter::formatUtc($alert->getFallDetectedAt());
        $provider = $this->pushGateway->getProviderName();
        $attempted = 0;
        $sentCount = 0;

        foreach ($links as $link) {
            $caregiverDevice = $link->getCaregiverDevice();
            $pushToken = $this->pushTokenRepository->findByDevice($caregiverDevice);

            if (!$pushToken instanceof CaregiverPushToken) {
                continue;
            }

            ++$attempted;
            $attempt = new PushAttempt($alert, $caregiverDevice, $provider);
            $alert->addPushAttempt($attempt);

            try {
                $result = $this->pushGateway->send(
                    $pushToken->getFcmToken(),
                    $alert->getId()->toRfc4122(),
                    $fallTimestamp,
                    $alert->getLatitude(),
                    $alert->getLongitude(),
                );
                $attempt->markSent($result['providerMessageId']);
                ++$sentCount;
            } catch (Throwable $exception) {
                $attempt->markFailed((string) $exception->getCode(), $exception->getMessage());
            }
        }

        if (0 === $attempted || 0 === $sentCount) {
            $alert->markFailed();
        } elseif ($sentCount < $attempted) {
            $alert->markPartiallySent();
        } else {
            $alert->markSent();
        }

        $this->fallAlertRepository->save($alert);
    }
}
