<?php

declare(strict_types=1);

namespace App\Domain\Device\Service;

use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Entity\Device;
use App\Entity\ProtectedPerson;
use DomainException;

final readonly class DeviceRevocationService
{
    public function __construct(private DeviceRepositoryInterface $deviceRepository)
    {
    }

    public function revoke(Device $requestingDevice, string $targetPublicId): void
    {
        $target = $this->deviceRepository->findByPublicId($targetPublicId);

        if (!$target instanceof Device) {
            throw new DomainException('Device not found.');
        }

        if (!$this->canRevoke($requestingDevice, $target)) {
            throw new DomainException('This device cannot revoke the requested device.');
        }

        $target->revoke();
        $this->deviceRepository->save($target);
    }

    private function canRevoke(Device $requestingDevice, Device $target): bool
    {
        if ($requestingDevice->getId()->equals($target->getId())) {
            return true;
        }

        if ($requestingDevice->isCaregiver() || $target->isCaregiver()) {
            return false;
        }

        $requestingPerson = $requestingDevice->getProtectedPerson();
        $targetPerson = $target->getProtectedPerson();

        return $requestingPerson instanceof ProtectedPerson
            && $targetPerson instanceof ProtectedPerson
            && $requestingPerson->getId()->equals($targetPerson->getId());
    }
}
