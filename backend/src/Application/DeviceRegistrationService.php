<?php

declare(strict_types=1);

namespace App\Application;

use App\Entity\Device;
use App\Security\DeviceTokenHasher;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Uid\Uuid;

final class DeviceRegistrationService
{
    public function __construct(
        private readonly DeviceTokenHasher $tokenHasher,
        private readonly EntityManagerInterface $entityManager,
    ) {
    }

    /** @return array{deviceId: string, deviceToken: string} */
    public function register(string $platform, string $appVersion): array
    {
        $plainToken = $this->tokenHasher->generatePlainToken();
        $device = new Device(Uuid::v7()->toRfc4122(), $this->tokenHasher->hash($plainToken), $platform, $appVersion);

        $this->entityManager->persist($device);
        $this->entityManager->flush();

        return [
            'deviceId' => $device->getPublicId(),
            'deviceToken' => $plainToken,
        ];
    }
}
