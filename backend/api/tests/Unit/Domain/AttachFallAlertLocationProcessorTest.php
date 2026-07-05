<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Processor\AttachFallAlertLocationProcessor;
use App\Domain\Alert\Request\AttachFallAlertLocationInputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Uid\Uuid;

final class AttachFallAlertLocationProcessorTest extends TestCase
{
    private AlertIngestionServiceInterface&MockObject $alertIngestionService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private AttachFallAlertLocationProcessor $processor;

    protected function setUp(): void
    {
        $this->alertIngestionService = $this->createMock(AlertIngestionServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->processor = new AttachFallAlertLocationProcessor($this->alertIngestionService, $this->currentDeviceProvider);
    }

    #[Test]
    public function itAttachesLocationAndReturnsOutputDTO(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->buildAlertMock();
        $dto = $this->buildDto(48.8566, 2.3522);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->expects($this->once())
            ->method('attachLocation')
            ->with($device, 'client-001', 48.8566, 2.3522)
            ->willReturn($alert);

        $result = $this->processor->process($dto, $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);

        $this->assertSame('client-001', $result->clientAlertId);
    }

    #[Test]
    public function itThrowsNotFoundWhenAlertNotFound(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->method('attachLocation')->willReturn(null);

        $this->expectException(NotFoundHttpException::class);

        $this->processor->process($this->buildDto(48.8566, 2.3522), $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);
    }

    #[Test]
    public function itThrowsNotFoundWhenClientAlertIdMissing(): void
    {
        $this->expectException(NotFoundHttpException::class);

        $this->processor->process($this->buildDto(48.8566, 2.3522), $this->createMock(Operation::class), []);
    }

    #[Test]
    public function itRejectsCaregiverDevices(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(true);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->expects($this->never())->method('attachLocation');

        $this->expectException(AccessDeniedHttpException::class);

        $this->processor->process($this->buildDto(48.8566, 2.3522), $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);
    }

    #[Test]
    public function itThrowsBadRequestForWrongPayloadType(): void
    {
        $this->expectException(BadRequestHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);
    }

    private function buildDto(?float $latitude, ?float $longitude): AttachFallAlertLocationInputDTO
    {
        $dto = new AttachFallAlertLocationInputDTO();
        $dto->latitude = $latitude;
        $dto->longitude = $longitude;

        return $dto;
    }

    private function buildAlertMock(): FallAlert&MockObject
    {
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getClientAlertId')->willReturn('client-001');
        $alert->method('getStatus')->willReturn(FallAlertStatus::Received);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getCancelledAt')->willReturn(null);

        return $alert;
    }
}
