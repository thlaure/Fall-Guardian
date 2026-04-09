<?php

declare(strict_types=1);

namespace App\Application;

interface SmsGateway
{
    /** @return array{providerMessageId: ?string, status: string} */
    public function send(string $to, string $body): array;
}
