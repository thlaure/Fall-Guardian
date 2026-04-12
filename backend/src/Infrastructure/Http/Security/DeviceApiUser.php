<?php

declare(strict_types=1);

namespace App\Infrastructure\Http\Security;

use App\Entity\Device;

use function sprintf;

use Symfony\Component\Security\Core\User\UserInterface;

final readonly class DeviceApiUser implements UserInterface
{
    public function __construct(private Device $device)
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
