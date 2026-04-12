<?php

declare(strict_types=1);

namespace App\Application;

interface SmsGateway
{
    public function getProviderName(): string;

    /** @return array{providerMessageId: ?string, status: string} */
    public function send(string $to, string $body): array;
}
