<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\ProtectedPerson\Provider\LinkedCaregiversProvider;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class LinkedCaregiversProviderTest extends TestCase
{
    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private CaregiverLinkRepositoryInterface&MockObject $caregiverLinkRepository;

    private LinkedCaregiversProvider $provider;

    protected function setUp(): void
    {
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->caregiverLinkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);

        $this->provider = new LinkedCaregiversProvider(
            $this->currentDeviceProvider,
            $this->caregiverLinkRepository,
        );
    }

    #[Test]
    public function itReturnsEmptyWhenNoLinks(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->caregiverLinkRepository->method('findActiveByProtectedDevice')->willReturn([]);

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertSame([], $result);
    }

    #[Test]
    public function itReturnsDTOsForEachLink(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('getPlatform')->willReturn('android');
        $caregiverDevice->method('getPublicId')->willReturn('caregiver-device-abc');

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiverDevice);
        $link->method('getCreatedAt')->willReturn(new DateTimeImmutable('2025-01-15T10:00:00+00:00'));

        $this->currentDeviceProvider->method('requireDevice')->willReturn($protectedDevice);
        $this->caregiverLinkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertCount(1, $result);
        $this->assertSame('android', $result[0]->platform);
        $this->assertSame('caregiver-device-abc', $result[0]->caregiverDeviceId);
        $this->assertStringContainsString('2025-01-15', $result[0]->linkedAt);
    }
}
