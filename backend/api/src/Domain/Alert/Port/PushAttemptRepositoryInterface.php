<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\FallAlert;
use App\Entity\PushAttempt;

interface PushAttemptRepositoryInterface
{
    public function save(PushAttempt $attempt): void;

    /**
     * Caregiver devices (RFC 4122 ids) that already received a successful push
     * for this alert in the given round (0 = initial alert, N = N-th reminder).
     *
     * @return list<string>
     */
    public function findSentCaregiverDeviceIds(FallAlert $alert, int $reminderNumber): array;
}
