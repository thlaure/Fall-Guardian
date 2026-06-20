<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Infrastructure\Push\DelegatingPushGateway;
use App\Infrastructure\Push\FakePushGateway;
use App\Infrastructure\Push\FakePushStore;
use App\Infrastructure\Push\FcmPushGateway;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Symfony\Contracts\HttpClient\HttpClientInterface;

final class DelegatingPushGatewayTest extends TestCase
{
    private FcmPushGateway $fcmGateway;

    private FakePushGateway $fakeGateway;

    protected function setUp(): void
    {
        $this->fcmGateway = new FcmPushGateway($this->createMock(HttpClientInterface::class), 'project-id', '{}');
        $this->fakeGateway = new FakePushGateway(new FakePushStore(sys_get_temp_dir(), 'fall-guardian-test-push'));
    }

    #[Test]
    public function itDelegatesToFakeGateway(): void
    {
        $gateway = new DelegatingPushGateway('fake', $this->fcmGateway, $this->fakeGateway);

        $this->assertSame('fake', $gateway->getProviderName());
        $result = $gateway->send('token', 'alert-id', '2025-01-01T00:00:00+00:00', null, null);
        $this->assertStringStartsWith('fake-push-', (string) $result['providerMessageId']);
    }

    #[Test]
    public function itDelegatesToFcmGateway(): void
    {
        $gateway = new DelegatingPushGateway('fcm', $this->fcmGateway, $this->fakeGateway);

        $this->assertSame('fcm', $gateway->getProviderName());
    }

    #[Test]
    public function itThrowsForUnknownProvider(): void
    {
        $gateway = new DelegatingPushGateway('unknown', $this->fcmGateway, $this->fakeGateway);

        $this->expectException(InvalidArgumentException::class);

        $gateway->send('token', 'alert-id', '2025-01-01T00:00:00+00:00', null, null);
    }
}
