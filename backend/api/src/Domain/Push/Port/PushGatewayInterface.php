<?php

declare(strict_types=1);

namespace App\Domain\Push\Port;

use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;

interface PushGatewayInterface
{
    public function getProviderName(): string;

    /**
     * @throws InvalidPushTokenException      when the token is permanently invalid and must be removed
     * @throws TransientPushDeliveryException when delivery may succeed on a later retry
     *
     * @return array{providerMessageId: ?string, status: string}
     */
    public function send(string $fcmToken, FallAlertPushPayload $payload): array;

    /**
     * @throws InvalidPushTokenException
     * @throws TransientPushDeliveryException
     *
     * @return array{providerMessageId: ?string, status: string}
     */
    public function sendLinkRevoked(string $fcmToken): array;
}
