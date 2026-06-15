<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Processor\CreateFallAlertProcessor;
use App\Domain\Alert\Request\CreateFallAlertInputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\Uid\Uuid;

final class CreateFallAlertProcessorTest extends TestCase
{
    private AlertIngestionServiceInterface&MockObject $alertIngestionService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private EndpointRateLimiterInterface&MockObject $rateLimiter;

    private CreateFallAlertProcessor $processor;

    protected function setUp(): void
    {
        $this->alertIngestionService = $this->createMock(AlertIngestionServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $this->processor = new CreateFallAlertProcessor($this->alertIngestionService, $this->currentDeviceProvider, $this->rateLimiter);
    }

    #[Test]
    public function itCreatesAlertAndReturnsOutputDTO(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('device-1');
        $alert = $this->buildAlertMock('client-001');

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->rateLimiter->expects($this->once())->method('consume')->with('fall_alert_create', 6, 60, 'device-1');
        $this->alertIngestionService->method('createAlert')->willReturn($alert);

        $data = new CreateFallAlertInputDTO();
        $data->clientAlertId = 'client-001';
        $data->locale = 'en';
        $data->fallTimestamp = new DateTimeImmutable();

        $result = $this->processor->process($data, $this->createMock(Operation::class));

        $this->assertSame('client-001', $result->clientAlertId);
        $this->assertSame('received', $result->status);
    }

    #[Test]
    public function itCreatesCancelledAlertWhenPayloadMarksItCancelled(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('device-1');
        $alert = $this->buildAlertMock('client-cancelled-001', FallAlertStatus::Cancelled);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->rateLimiter->expects($this->once())->method('consume')->with('fall_alert_create', 6, 60, 'device-1');
        $this->alertIngestionService->expects($this->never())->method('createAlert');
        $this->alertIngestionService->expects($this->once())->method('createCancelledAlert')->willReturn($alert);

        $data = new CreateFallAlertInputDTO();
        $data->clientAlertId = 'client-cancelled-001';
        $data->locale = 'en';
        $data->fallTimestamp = new DateTimeImmutable();
        $data->cancelled = true;

        $result = $this->processor->process($data, $this->createMock(Operation::class));

        $this->assertSame('client-cancelled-001', $result->clientAlertId);
        $this->assertSame('cancelled', $result->status);
    }

    #[Test]
    public function itFallsBackToNowWhenTimestampAbsent(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('device-2');
        $alert = $this->buildAlertMock('client-002');

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->method('createAlert')->willReturn($alert);

        $data = new CreateFallAlertInputDTO();
        $data->clientAlertId = 'client-002';
        $data->locale = 'fr';

        $result = $this->processor->process($data, $this->createMock(Operation::class));

        $this->assertSame('client-002', $result->clientAlertId);
    }

    #[Test]
    public function itRejectsCaregiverDevices(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(true);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->expects($this->never())->method('createAlert');

        $data = new CreateFallAlertInputDTO();
        $data->clientAlertId = 'client-caregiver';
        $data->locale = 'en';

        $this->expectException(AccessDeniedHttpException::class);

        $this->processor->process($data, $this->createMock(Operation::class));
    }

    private function buildAlertMock(string $clientAlertId, FallAlertStatus $status = FallAlertStatus::Received): FallAlert&MockObject
    {
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getClientAlertId')->willReturn($clientAlertId);
        $alert->method('getStatus')->willReturn($status);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getCancelledAt')->willReturn(
            FallAlertStatus::Cancelled === $status ? new DateTimeImmutable() : null,
        );

        return $alert;
    }
}
