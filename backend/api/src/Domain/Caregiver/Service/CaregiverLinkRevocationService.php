<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Service;

use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Entity\Device;

final readonly class CaregiverLinkRevocationService
{
    public function __construct(private CaregiverLinkRepositoryInterface $caregiverLinkRepository)
    {
    }

    public function revokeForCaregiver(Device $caregiverDevice, string $linkId): bool
    {
        $link = $this->caregiverLinkRepository->findActiveByIdAndCaregiverDevice($linkId, $caregiverDevice);

        if (null === $link) {
            return false;
        }

        $link->revoke();
        $this->caregiverLinkRepository->save($link);

        return true;
    }
}
