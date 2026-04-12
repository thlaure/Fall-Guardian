<?php

declare(strict_types=1);

namespace App\Infrastructure\Http\Security;

use App\Entity\Device;
use RuntimeException;
use Symfony\Component\Security\Core\Authentication\Token\Storage\TokenStorageInterface;

final readonly class CurrentDeviceProvider
{
    public function __construct(private TokenStorageInterface $tokenStorage)
    {
    }

    public function requireDevice(): Device
    {
        $user = $this->tokenStorage->getToken()?->getUser();

        if (!$user instanceof DeviceApiUser) {
            throw new RuntimeException('Authenticated device context is missing.');
        }

        return $user->getDevice();
    }
}
