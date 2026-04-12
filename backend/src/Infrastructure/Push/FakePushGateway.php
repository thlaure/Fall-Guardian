<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Port\PushGatewayInterface;

use function sprintf;

use Symfony\Component\Uid\Uuid;

final readonly class FakePushGateway implements PushGatewayInterface
{
    public function __construct(private FakePushStore $store)
    {
    }

    public function getProviderName(): string
    {
        return 'fake';
    }

    public function send(string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): array
    {
        $providerMessageId = sprintf('fake-push-%s', Uuid::v7()->toRfc4122());
        $this->store->append($providerMessageId, $fcmToken, $alertId, $fallTimestamp, $latitude, $longitude);

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }
}
