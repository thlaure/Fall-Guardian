<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Port;

use App\Entity\CaregiverPushToken;
use App\Entity\Device;

interface CaregiverPushTokenRepositoryInterface
{
    public function findByDevice(Device $device): ?CaregiverPushToken;

    public function findByDeviceId(string $deviceId): ?CaregiverPushToken;

    public function save(CaregiverPushToken $token): void;

    /**
     * Deletes the device's push token only if it still holds `$fcmToken`, so a
     * token re-registered meanwhile is never removed by a stale failure.
     */
    public function deleteIfUnchanged(Device $device, string $fcmToken): bool;
}
