<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Port;

use App\Entity\CaregiverInvite;

interface CaregiverInviteRepositoryInterface
{
    public function findActiveByCode(string $code): ?CaregiverInvite;

    public function save(CaregiverInvite $invite): void;
}
