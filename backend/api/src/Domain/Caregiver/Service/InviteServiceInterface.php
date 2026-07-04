<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Service;

use App\Entity\CaregiverInvite;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;

interface InviteServiceInterface
{
    public function createInvite(Device $protectedDevice): CaregiverInvite;

    public function acceptInvite(
        string $code,
        Device $caregiverDevice,
        ?string $protectedPersonName = null,
        ?string $caregiverName = null,
    ): CaregiverLink;

    public function registerPushToken(Device $caregiverDevice, string $fcmToken): CaregiverPushToken;
}
