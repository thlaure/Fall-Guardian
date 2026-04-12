<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\SmsAttempt;

interface SmsAttemptRepositoryInterface
{
    public function findOneByProviderMessageId(string $providerMessageId): ?SmsAttempt;

    public function save(SmsAttempt $attempt): void;
}
