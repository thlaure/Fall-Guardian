<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Provider\LinkedProtectedPersonsProvider;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class LinkedProtectedPersonsProviderTest extends TestCase
{
    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private CaregiverLinkRepositoryInterface&MockObject $caregiverLinkRepository;

    private LinkedProtectedPersonsProvider $provider;

    protected function setUp(): void
    {
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->caregiverLinkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->provider = new LinkedProtectedPersonsProvider(
            $this->currentDeviceProvider,
            $this->caregiverLinkRepository,
        );
    }

    #[Test]
    public function itReturnsLinkedProtectedPersonsForCaregiver(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $protectedDevice = $this->createMock(Device::class);
        $protectedDevice->method('getPublicId')->willReturn('protected-1');
        $protectedDevice->method('getPlatform')->willReturn('ios');

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getProtectedDevice')->willReturn($protectedDevice);
        $link->method('getCreatedAt')->willReturn(new DateTimeImmutable('2026-06-15T10:00:00+00:00'));

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->caregiverLinkRepository->method('findByCaregiverDevice')->with($caregiverDevice)->willReturn([$link]);

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertCount(1, $result);
        $this->assertSame('protected-1', $result[0]->protectedDeviceId);
        $this->assertSame('ios', $result[0]->protectedDevicePlatform);
    }

    #[Test]
    public function itReturnsEmptyListWhenCaregiverHasNoLinks(): void
    {
        $caregiverDevice = $this->createMock(Device::class);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->caregiverLinkRepository->method('findByCaregiverDevice')->with($caregiverDevice)->willReturn([]);

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertSame([], $result);
    }
}
