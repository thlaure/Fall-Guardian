<?php

declare(strict_types=1);

namespace App\Security;

use App\Entity\Device;

use function sprintf;

use Symfony\Component\Security\Core\User\UserInterface;

final class DeviceApiUser implements UserInterface
{
    public function __construct(private readonly Device $device)
    {
    }

    public function getDevice(): Device
    {
        return $this->device;
    }

    public function getRoles(): array
    {
        return ['ROLE_DEVICE'];
    }

    public function eraseCredentials(): void
    {
    }

    public function getUserIdentifier(): string
    {
        return sprintf('device:%s', $this->device->getPublicId());
    }
}
