<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Model;

use App\Entity\CaregiverInvite;

/**
 * A freshly created invite together with its plaintext code. The plaintext is
 * only available here, once, so it can be returned to the creating device;
 * the database stores an HMAC of it.
 */
final readonly class IssuedInvite
{
    public function __construct(
        public CaregiverInvite $invite,
        public string $code,
    ) {
    }
}
