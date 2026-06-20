<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Entity\Device;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;
use App\Infrastructure\Http\Security\DeviceApiUser;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use RuntimeException;
use Symfony\Component\Security\Core\Authentication\Token\Storage\TokenStorageInterface;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;

final class CurrentDeviceProviderTest extends TestCase
{
    private TokenStorageInterface&MockObject $tokenStorage;

    private CurrentDeviceProvider $provider;

    protected function setUp(): void
    {
        $this->tokenStorage = $this->createMock(TokenStorageInterface::class);
        $this->provider = new CurrentDeviceProvider($this->tokenStorage);
    }

    #[Test]
    public function itReturnsDeviceFromAuthenticatedToken(): void
    {
        $device = $this->createMock(Device::class);
        $user = new DeviceApiUser($device);

        $token = $this->createMock(TokenInterface::class);
        $token->method('getUser')->willReturn($user);

        $this->tokenStorage->method('getToken')->willReturn($token);

        $result = $this->provider->requireDevice();

        $this->assertSame($device, $result);
    }

    #[Test]
    public function itThrowsWhenNoToken(): void
    {
        $this->tokenStorage->method('getToken')->willReturn(null);

        $this->expectException(RuntimeException::class);

        $this->provider->requireDevice();
    }

    #[Test]
    public function itThrowsWhenUserIsNotDeviceApiUser(): void
    {
        $token = $this->createMock(TokenInterface::class);
        $token->method('getUser')->willReturn(null);
        $this->tokenStorage->method('getToken')->willReturn($token);

        $this->expectException(RuntimeException::class);

        $this->provider->requireDevice();
    }
}
