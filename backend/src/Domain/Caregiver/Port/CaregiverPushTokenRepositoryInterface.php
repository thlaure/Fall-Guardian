<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Port;

use App\Entity\CaregiverPushToken;
use App\Entity\Device;

interface CaregiverPushTokenRepositoryInterface
{
    public function findByDevice(Device $device): ?CaregiverPushToken;

    public function save(CaregiverPushToken $token): void;
}
