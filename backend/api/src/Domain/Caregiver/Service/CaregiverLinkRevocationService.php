<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Service;

use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use RuntimeException;
use Throwable;

final readonly class CaregiverLinkRevocationService
{
    public function __construct(
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private CaregiverPushTokenRepositoryInterface $pushTokenRepository,
        private PushGatewayInterface $pushGateway,
    ) {
    }

    public function revoke(Device $protectedDevice, string $linkId): void
    {
        $link = $this->caregiverLinkRepository->findActiveByIdAndProtectedDevice($linkId, $protectedDevice);

        if (null === $link) {
            throw new RuntimeException('Caregiver link not found.');
        }

        $link->revoke();
        $this->caregiverLinkRepository->save($link);

        $pushToken = $this->pushTokenRepository->findByDevice($link->getCaregiverDevice());

        if (!$pushToken instanceof CaregiverPushToken) {
            return;
        }

        try {
            $this->pushGateway->sendLinkRevoked($pushToken->getFcmToken());
        } catch (Throwable) {
            // Best-effort notice only: the link is already revoked and the
            // push handler independently excludes revoked links and devices.
        }
    }
}
