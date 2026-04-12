<?php

declare(strict_types=1);

namespace App\Application\Alert\Handler;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\FallAlert;
use App\Entity\PushAttempt;
use App\Message\SendFallAlertPushMessage;
use DateTimeImmutable;
use DateTimeInterface;
use Doctrine\ORM\EntityManagerInterface;
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
        private EntityManagerInterface $entityManager,
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

        $fallTimestamp = $alert->getFallDetectedAt()->format(DateTimeInterface::ATOM);
        $provider = $this->pushGateway->getProviderName();
        $sentCount = 0;

        foreach ($links as $link) {
            $caregiverDevice = $link->getCaregiverDevice();
            $pushToken = $this->pushTokenRepository->findByDevice($caregiverDevice);

            if (!$pushToken instanceof \App\Entity\CaregiverPushToken) {
                continue;
            }

            $attempt = new PushAttempt($alert, $caregiverDevice, $provider);
            $alert->addPushAttempt($attempt);
            $this->entityManager->persist($attempt);

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

        $this->entityManager->flush();
    }
}
