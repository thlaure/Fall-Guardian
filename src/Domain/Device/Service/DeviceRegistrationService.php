<?php

declare(strict_types=1);

namespace App\Domain\Device\Service;

use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Entity\Device;
use App\Enum\DeviceType;
use App\Infrastructure\Http\Security\DeviceTokenHasher;
use Symfony\Component\Uid\Uuid;

final readonly class DeviceRegistrationService
{
    public function __construct(
        private DeviceTokenHasher $tokenHasher,
        private DeviceRepositoryInterface $deviceRepository,
    ) {
    }

    public function register(string $platform, string $appVersion, DeviceType $deviceType = DeviceType::ProtectedPerson): DeviceRegistrationOutputDTO
    {
        $plainToken = $this->tokenHasher->generatePlainToken();
        $device = new Device(Uuid::v7()->toRfc4122(), $this->tokenHasher->hash($plainToken), $platform, $appVersion);
        $device->setDeviceType($deviceType);

        $this->deviceRepository->save($device);

        return new DeviceRegistrationOutputDTO($device->getPublicId(), $plainToken);
    }
}
