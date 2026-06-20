<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Handler;

use App\Domain\Caregiver\Message\NotifyCaregiverLinkRevokedMessage;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverPushToken;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final readonly class NotifyCaregiverLinkRevokedMessageHandler
{
    public function __construct(
        private CaregiverPushTokenRepositoryInterface $pushTokenRepository,
        private PushGatewayInterface $pushGateway,
    ) {
    }

    public function __invoke(NotifyCaregiverLinkRevokedMessage $message): void
    {
        $token = $this->pushTokenRepository->findByDeviceId($message->caregiverDeviceId);

        if (!$token instanceof CaregiverPushToken) {
            return;
        }

        $this->pushGateway->sendLinkRevoked($token->getFcmToken());
    }
}
