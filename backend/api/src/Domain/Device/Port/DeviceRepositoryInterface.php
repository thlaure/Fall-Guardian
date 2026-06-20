<?php

declare(strict_types=1);

namespace App\Domain\Device\Port;

use App\Entity\Device;

interface DeviceRepositoryInterface
{
    public function findActiveByTokenHash(string $tokenHash): ?Device;

    public function save(Device $device): void;
}
