<?php

declare(strict_types=1);

namespace App\Domain\Contact\Port;

use App\Entity\Device;
use App\Entity\EmergencyContact;

interface EmergencyContactRepositoryInterface
{
    /** @return list<EmergencyContact> */
    public function findByDevice(Device $device): array;

    public function deleteForDevice(Device $device): void;
}
