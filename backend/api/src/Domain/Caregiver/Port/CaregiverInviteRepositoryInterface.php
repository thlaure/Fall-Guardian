<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Port;

use App\Entity\CaregiverInvite;

interface CaregiverInviteRepositoryInterface
{
    public function findActiveByCodeHash(string $codeHash): ?CaregiverInvite;

    /**
     * Transition fallback for invites issued before codes were hashed. Only
     * rows without a code hash are matched; they expire within the invite TTL.
     */
    public function findActiveLegacyByPlainCode(string $code): ?CaregiverInvite;

    public function save(CaregiverInvite $invite): void;
}
