<?php

declare(strict_types=1);

namespace App\Domain\Push\Port;

interface PushGatewayInterface
{
    public function getProviderName(): string;

    /** @return array{providerMessageId: ?string, status: string} */
    public function send(string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): array;
}
