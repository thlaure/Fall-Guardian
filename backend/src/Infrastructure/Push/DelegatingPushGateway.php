<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Port\PushGatewayInterface;
use InvalidArgumentException;

use function sprintf;

final readonly class DelegatingPushGateway implements PushGatewayInterface
{
    public function __construct(
        private string $provider,
        private FcmPushGateway $fcmPushGateway,
        private FakePushGateway $fakePushGateway,
    ) {
    }

    public function getProviderName(): string
    {
        return $this->inner()->getProviderName();
    }

    public function send(string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): array
    {
        return $this->inner()->send($fcmToken, $alertId, $fallTimestamp, $latitude, $longitude);
    }

    private function inner(): PushGatewayInterface
    {
        return match ($this->provider) {
            'fcm' => $this->fcmPushGateway,
            'fake' => $this->fakePushGateway,
            default => throw new InvalidArgumentException(sprintf('Unsupported push provider "%s".', $this->provider)),
        };
    }
}
