<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Processor\AcknowledgeAlertProcessor;
use App\Entity\AlertAcknowledgement;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Uid\Uuid;

final class AcknowledgeAlertProcessorTest extends TestCase
{
    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private FallAlertRepositoryInterface&MockObject $fallAlertRepository;

    private CaregiverLinkRepositoryInterface&MockObject $caregiverLinkRepository;

    private AlertAcknowledgementRepositoryInterface&MockObject $acknowledgementRepository;

    private EndpointRateLimiterInterface&MockObject $rateLimiter;

    private AcknowledgeAlertProcessor $processor;

    protected function setUp(): void
    {
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->fallAlertRepository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->caregiverLinkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->acknowledgementRepository = $this->createMock(AlertAcknowledgementRepositoryInterface::class);
        $this->rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $this->processor = new AcknowledgeAlertProcessor(
            $this->currentDeviceProvider,
            $this->fallAlertRepository,
            $this->caregiverLinkRepository,
            $this->acknowledgementRepository,
            $this->rateLimiter,
        );
    }

    #[Test]
    public function itAcknowledgesAlertWhenLinked(): void
    {
        $caregiverId = Uuid::v7();
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('getId')->willReturn($caregiverId);
        $caregiverDevice->method('getPublicId')->willReturn('caregiver-device-1');

        $protectedDevice = $this->createMock(Device::class);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->expects($this->once())->method('markAcknowledged');

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiverDevice);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->caregiverLinkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);
        $this->acknowledgementRepository->method('findByCaregiverAndAlert')->willReturn(null);
        $this->acknowledgementRepository->expects($this->once())->method('save');
        $this->rateLimiter->expects($this->once())->method('consume')->with('acknowledge_alert', 20, 60, 'caregiver-device-1');

        $result = $this->processor->process(null, $this->createMock(Operation::class), ['id' => 'some-uuid']);

        $this->assertNull($result);
    }

    #[Test]
    public function itSkipsAcknowledgementWhenAlreadyAcknowledged(): void
    {
        $caregiverId = Uuid::v7();
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('getId')->willReturn($caregiverId);

        $protectedDevice = $this->createMock(Device::class);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->expects($this->never())->method('markAcknowledged');

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiverDevice);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->caregiverLinkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);
        $this->acknowledgementRepository->method('findByCaregiverAndAlert')->willReturn(
            $this->createMock(AlertAcknowledgement::class),
        );

        $result = $this->processor->process(null, $this->createMock(Operation::class), ['id' => 'some-uuid']);

        $this->assertNull($result);
    }

    #[Test]
    public function itThrowsNotFoundWhenAlertMissing(): void
    {
        $this->fallAlertRepository->method('findById')->willReturn(null);

        $this->expectException(NotFoundHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['id' => 'unknown']);
    }

    #[Test]
    public function itThrowsAccessDeniedWhenNotLinked(): void
    {
        $caregiverId = Uuid::v7();
        $otherDeviceId = Uuid::v7();

        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('getId')->willReturn($caregiverId);

        $otherDevice = $this->createMock(Device::class);
        $otherDevice->method('getId')->willReturn($otherDeviceId);

        $protectedDevice = $this->createMock(Device::class);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($protectedDevice);

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($otherDevice);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($caregiverDevice);
        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->caregiverLinkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);

        $this->expectException(AccessDeniedHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['id' => 'some-uuid']);
    }
}
