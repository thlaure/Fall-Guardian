<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\PermanentPushDeliveryException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Infrastructure\Push\FakePushGateway;
use App\Infrastructure\Push\FakePushStore;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class FakePushGatewayTest extends TestCase
{
    private string $shareDir;

    private FakePushStore $store;

    private FakePushGateway $gateway;

    protected function setUp(): void
    {
        $this->shareDir = 'fall-guardian-fake-push-test';
        $this->store = new FakePushStore(sys_get_temp_dir(), $this->shareDir);
        $this->store->clear();
        $this->gateway = new FakePushGateway($this->store);
    }

    #[Test]
    public function itReturnsProviderName(): void
    {
        $this->assertSame('fake', $this->gateway->getProviderName());
    }

    #[Test]
    public function itAppendsToStoreAndReturnsProviderMessageId(): void
    {
        $result = $this->gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2025-01-01T00:00:00+00:00', '2025-01-01T00:00:30+00:00', 48.8, 2.3));

        $this->assertArrayHasKey('providerMessageId', $result);
        $this->assertStringStartsWith('fake-push-', $result['providerMessageId']);
        $this->assertSame('sent', $result['status']);

        $entries = $this->store->all();
        $this->assertCount(1, $entries);
        $this->assertSame($result['providerMessageId'], $entries[0]['providerMessageId']);
        $this->assertSame('fcm-token', $entries[0]['fcmToken']);
        $this->assertSame('alert-id', $entries[0]['alertId']);
        $this->assertSame('48.8', $entries[0]['latitude']);
        $this->assertSame('2.3', $entries[0]['longitude']);
    }

    #[Test]
    public function itAppendsLinkRevokedNotificationToStore(): void
    {
        $result = $this->gateway->sendLinkRevoked('fcm-token');

        $this->assertArrayHasKey('providerMessageId', $result);
        $this->assertStringStartsWith('fake-push-revoked-', $result['providerMessageId']);
        $this->assertSame('sent', $result['status']);

        $contents = file_get_contents(sprintf('%s/%s/fake_push_inbox.jsonl', sys_get_temp_dir(), $this->shareDir));
        $this->assertIsString($contents);

        $entry = json_decode(trim($contents), true);
        $this->assertIsArray($entry);
        $this->assertSame($result['providerMessageId'], $entry['providerMessageId'] ?? null);
        $this->assertSame('fcm-token', $entry['fcmToken'] ?? null);
        $this->assertSame('caregiver_revoked', $entry['type'] ?? null);
    }

    #[Test]
    public function itRecordsTheNewContractKeys(): void
    {
        $this->gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2025-01-01T00:00:00Z', '2025-01-01T00:00:30Z', null, null, 'Mamie', true));

        $entry = $this->store->all()[0];
        $this->assertSame('2025-01-01T00:00:30Z', $entry['cancelDeadlineAt']);
        $this->assertSame('Mamie', $entry['protectedPersonName']);
        $this->assertSame('1', $entry['reminder']);
    }

    #[Test]
    public function itSimulatesAnInvalidToken(): void
    {
        $this->expectException(InvalidPushTokenException::class);

        $this->gateway->send(FakePushGateway::INVALID_TOKEN_PREFIX.'x', new FallAlertPushPayload('alert-id', '2025-01-01T00:00:00Z', '2025-01-01T00:00:30Z'));
    }

    #[Test]
    public function itSimulatesAnUnavailableProvider(): void
    {
        $this->expectException(TransientPushDeliveryException::class);

        $this->gateway->sendLinkRevoked(FakePushGateway::UNAVAILABLE_TOKEN_PREFIX.'x');
    }

    #[Test]
    public function itSimulatesARejectedMessage(): void
    {
        $this->expectException(PermanentPushDeliveryException::class);

        $this->gateway->send(FakePushGateway::REJECTED_TOKEN_PREFIX.'x', new FallAlertPushPayload('alert-id', '2025-01-01T00:00:00Z', '2025-01-01T00:00:30Z'));
    }
}
