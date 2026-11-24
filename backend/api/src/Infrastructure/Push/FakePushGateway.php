<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Domain\Push\Port\PushGatewayInterface;
use Symfony\Component\Uid\Uuid;

final readonly class FakePushGateway implements PushGatewayInterface
{
    /** Tokens with this prefix simulate a provider-side permanently invalid token (e.g. FCM UNREGISTERED). */
    public const string INVALID_TOKEN_PREFIX = 'fake-invalid-';

    /** Tokens with this prefix simulate a transient provider outage (e.g. FCM HTTP 503). */
    public const string UNAVAILABLE_TOKEN_PREFIX = 'fake-unavailable-';

    public function __construct(private FakePushStore $store)
    {
    }

    public function getProviderName(): string
    {
        return 'fake';
    }

    public function send(string $fcmToken, FallAlertPushPayload $payload): array
    {
        $this->simulateFailures($fcmToken);

        $providerMessageId = sprintf('fake-push-%s', Uuid::v7()->toRfc4122());
        $this->store->append($providerMessageId, $fcmToken, $payload);

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }

    public function sendLinkRevoked(string $fcmToken): array
    {
        $this->simulateFailures($fcmToken);

        $providerMessageId = sprintf('fake-push-revoked-%s', Uuid::v7()->toRfc4122());
        $this->store->appendLinkRevoked($providerMessageId, $fcmToken);

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }

    private function simulateFailures(string $fcmToken): void
    {
        if (str_starts_with($fcmToken, self::INVALID_TOKEN_PREFIX)) {
            throw new InvalidPushTokenException('Fake push token is not registered.', 'UNREGISTERED');
        }

        if (str_starts_with($fcmToken, self::UNAVAILABLE_TOKEN_PREFIX)) {
            throw new TransientPushDeliveryException('Fake push provider is unavailable.', 'http_503');
        }
    }
}
