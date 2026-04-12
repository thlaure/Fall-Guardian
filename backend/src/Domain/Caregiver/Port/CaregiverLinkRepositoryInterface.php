<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Port;

use App\Entity\CaregiverLink;
use App\Entity\Device;

interface CaregiverLinkRepositoryInterface
{
    /** @return list<CaregiverLink> */
    public function findActiveByProtectedDevice(Device $protectedDevice): array;

    public function findExistingPair(Device $protectedDevice, Device $caregiverDevice): ?CaregiverLink;

    /** @return list<CaregiverLink> */
    public function findByCaregiverDevice(Device $caregiverDevice): array;

    public function save(CaregiverLink $link): void;
}
