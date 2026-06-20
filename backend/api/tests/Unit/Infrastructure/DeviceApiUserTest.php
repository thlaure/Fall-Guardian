<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceApiUser;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class DeviceApiUserTest extends TestCase
{
    private Device&MockObject $device;

    private DeviceApiUser $user;

    protected function setUp(): void
    {
        $this->device = $this->createMock(Device::class);
        $this->device->method('getPublicId')->willReturn('device-public-id');
        $this->user = new DeviceApiUser($this->device);
    }

    #[Test]
    public function itReturnsDevice(): void
    {
        $this->assertSame($this->device, $this->user->getDevice());
    }

    #[Test]
    public function itReturnsDeviceRole(): void
    {
        $this->assertSame(['ROLE_DEVICE'], $this->user->getRoles());
    }

    #[Test]
    public function itReturnsUserIdentifierWithDevicePrefix(): void
    {
        $this->assertSame('device:device-public-id', $this->user->getUserIdentifier());
    }

    #[Test]
    public function itErasesCredentialsWithoutError(): void
    {
        $this->user->eraseCredentials();
        $this->assertTrue(true);
    }
}
