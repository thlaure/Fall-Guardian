<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Port\PushGatewayInterface;
use Psr\Log\LoggerInterface;

use function sprintf;

use Symfony\Component\Uid\Uuid;

final readonly class FakePushGateway implements PushGatewayInterface
{
    public function __construct(private LoggerInterface $logger)
    {
    }

    public function getProviderName(): string
    {
        return 'fake';
    }

    public function send(string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): array
    {
        $providerMessageId = sprintf('fake-push-%s', Uuid::v7()->toRfc4122());

        $this->logger->info('FakePushGateway: push sent', [
            'providerMessageId' => $providerMessageId,
            'fcmToken' => substr($fcmToken, 0, 12) . '...',
            'alertId' => $alertId,
            'fallTimestamp' => $fallTimestamp,
            'latitude' => $latitude,
            'longitude' => $longitude,
        ]);

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }
}
