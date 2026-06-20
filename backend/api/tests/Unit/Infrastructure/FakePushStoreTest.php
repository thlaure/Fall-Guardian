<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Infrastructure\Push\FakePushStore;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class FakePushStoreTest extends TestCase
{
    private string $tmpDir;

    private FakePushStore $store;

    protected function setUp(): void
    {
        $this->tmpDir = sys_get_temp_dir();
        $shareDir = 'fake_push_test_'.uniqid();
        $this->store = new FakePushStore($this->tmpDir, $shareDir);
    }

    protected function tearDown(): void
    {
        $this->store->clear();
    }

    #[Test]
    public function itReturnsEmptyWhenFileDoesNotExist(): void
    {
        $result = $this->store->all();

        $this->assertSame([], $result);
    }

    #[Test]
    public function itAppendsAndReadsEntries(): void
    {
        $this->store->append('msg-001', 'fcm-token', 'alert-id', '2025-01-01T00:00:00+00:00', 48.8, 2.3);
        $this->store->append('msg-002', 'fcm-token-2', 'alert-id-2', '2025-01-02T00:00:00+00:00', null, null);

        $entries = $this->store->all();

        $this->assertCount(2, $entries);
        $this->assertSame('msg-001', $entries[0]['providerMessageId']);
        $this->assertSame('fcm-token', $entries[0]['fcmToken']);
        $this->assertSame('alert-id', $entries[0]['alertId']);
        $this->assertSame('48.8', $entries[0]['latitude']);
        $this->assertSame('2.3', $entries[0]['longitude']);
        $this->assertSame('msg-002', $entries[1]['providerMessageId']);
        $this->assertNull($entries[1]['latitude']);
        $this->assertNull($entries[1]['longitude']);
    }

    #[Test]
    public function itClearsEntries(): void
    {
        $this->store->append('msg-001', 'fcm-token', 'alert-id', '2025-01-01T00:00:00+00:00', null, null);
        $this->store->clear();

        $result = $this->store->all();

        $this->assertSame([], $result);
    }

    #[Test]
    public function itReturnsEmptyAfterClearOnNonExistentFile(): void
    {
        $this->store->clear();

        $this->assertSame([], $this->store->all());
    }
}
