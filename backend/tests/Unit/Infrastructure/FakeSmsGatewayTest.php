<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Infrastructure\Sms\FakeSmsGateway;
use App\Infrastructure\Sms\FakeSmsStore;
use PHPUnit\Framework\TestCase;

use function sys_get_temp_dir;
use function uniqid;

final class FakeSmsGatewayTest extends TestCase
{
    public function testItStoresOutgoingMessagesInTheFakeInbox(): void
    {
        $root = sys_get_temp_dir() . '/fall_guardian_fake_sms_' . uniqid('', true);
        $store = new FakeSmsStore($root, 'var/share');
        $gateway = new FakeSmsGateway($store);

        $result = $gateway->send('+33612345678', 'Test message');

        self::assertSame('fake', $gateway->getProviderName());
        self::assertSame('sent', $result['status']);
        self::assertStringStartsWith('fake-', (string) $result['providerMessageId']);

        $entries = $store->all();

        self::assertCount(1, $entries);
        self::assertSame('+33612345678', $entries[0]['to']);
        self::assertSame('Test message', $entries[0]['body']);
        self::assertSame($result['providerMessageId'], $entries[0]['providerMessageId']);
    }
}
