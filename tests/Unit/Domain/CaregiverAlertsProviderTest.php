<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Provider\CaregiverAlertsProvider;
use App\Entity\AlertAcknowledgement;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Uid\Uuid;

final class CaregiverAlertsProviderTest extends TestCase
{
    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private CaregiverLinkRepositoryInterface&MockObject $caregiverLinkRepository;

    private FallAlertRepositoryInterface&MockObject $fallAlertRepository;

    private AlertAcknowledgementRepositoryInterface&MockObject $acknowledgementRepository;

    private CaregiverAlertsProvider $provider;

    protected function setUp(): void
    {
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->caregiverLinkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->fallAlertRepository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->acknowledgementRepository = $this->createMock(AlertAcknowledgementRepositoryInterface::class);

        $this->provider = new CaregiverAlertsProvider(
            $this->currentDeviceProvider,
            $this->caregiverLinkRepository,
            $this->fallAlertRepository,
            $this->acknowledgementRepository,
        );
    }

    #[Test]
    public function itReturnsEmptyWhenNoLinks(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->caregiverLinkRepository->method('findByCaregiverDevice')->willReturn([]);

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertSame([], $result);
    }

    #[Test]
    public function itReturnsAlertsWithAcknowledgedFlag(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $protectedDevice = $this->createMock(Device::class);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getStatus')->willReturn(FallAlertStatus::Received);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getLatitude')->willReturn(null);
        $alert->method('getLongitude')->willReturn(null);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $protectedDevice->method('getPublicId')->willReturn('device-abc');
        $protectedDevice->method('getPlatform')->willReturn('ios');

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getProtectedDevice')->willReturn($protectedDevice);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->caregiverLinkRepository->method('findByCaregiverDevice')->willReturn([$link]);
        $this->fallAlertRepository->method('findByDevice')->willReturn([$alert]);
        $this->acknowledgementRepository->method('findByCaregiverAndAlert')->willReturn(
            $this->createMock(AlertAcknowledgement::class),
        );

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertCount(1, $result);
        $this->assertTrue($result[0]->acknowledged);
        $this->assertSame('device-abc', $result[0]->protectedDeviceId);
        $this->assertSame('ios', $result[0]->protectedDevicePlatform);
    }

    #[Test]
    public function itReturnsAlertsWithUnacknowledgedFlag(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $protectedDevice = $this->createMock(Device::class);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getStatus')->willReturn(FallAlertStatus::Received);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getLatitude')->willReturn(48.8);
        $alert->method('getLongitude')->willReturn(2.3);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $protectedDevice->method('getPublicId')->willReturn('device-xyz');
        $protectedDevice->method('getPlatform')->willReturn('android');

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getProtectedDevice')->willReturn($protectedDevice);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->caregiverLinkRepository->method('findByCaregiverDevice')->willReturn([$link]);
        $this->fallAlertRepository->method('findByDevice')->willReturn([$alert]);
        $this->acknowledgementRepository->method('findByCaregiverAndAlert')->willReturn(null);

        $result = $this->provider->provide($this->createMock(Operation::class));

        $this->assertCount(1, $result);
        $this->assertFalse($result[0]->acknowledged);
        $this->assertSame('device-xyz', $result[0]->protectedDeviceId);
        $this->assertSame('android', $result[0]->protectedDevicePlatform);
    }
}
