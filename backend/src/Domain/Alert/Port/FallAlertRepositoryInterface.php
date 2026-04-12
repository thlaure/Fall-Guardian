<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\Device;
use App\Entity\FallAlert;

interface FallAlertRepositoryInterface
{
    public function findOneByDeviceAndClientAlertId(Device $device, string $clientAlertId): ?FallAlert;

    public function findById(string $id): ?FallAlert;

    /** @return list<FallAlert> */
    public function findByDevice(Device $device, int $limit = 50): array;

    public function save(FallAlert $alert): void;
}
