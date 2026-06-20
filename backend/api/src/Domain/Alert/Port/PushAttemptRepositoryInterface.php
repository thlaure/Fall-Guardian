<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\PushAttempt;

interface PushAttemptRepositoryInterface
{
    public function save(PushAttempt $attempt): void;
}
