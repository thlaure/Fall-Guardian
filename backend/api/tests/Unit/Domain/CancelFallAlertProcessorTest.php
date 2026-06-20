<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Processor\CancelFallAlertProcessor;
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
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Uid\Uuid;

final class CancelFallAlertProcessorTest extends TestCase
{
    private AlertIngestionServiceInterface&MockObject $alertIngestionService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private CancelFallAlertProcessor $processor;

    protected function setUp(): void
    {
        $this->alertIngestionService = $this->createMock(AlertIngestionServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->processor = new CancelFallAlertProcessor($this->alertIngestionService, $this->currentDeviceProvider);
    }

    #[Test]
    public function itCancelsAlertAndReturnsOutputDTO(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->buildAlertMock();

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->method('cancelAlert')->willReturn($alert);

        $result = $this->processor->process(null, $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);

        $this->assertSame('cancelled', $result->status);
    }

    #[Test]
    public function itThrowsNotFoundWhenAlertNotFound(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->method('cancelAlert')->willReturn(null);

        $this->expectException(NotFoundHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);
    }

    #[Test]
    public function itThrowsNotFoundWhenClientAlertIdMissing(): void
    {
        $this->expectException(NotFoundHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), []);
    }

    #[Test]
    public function itRejectsCaregiverDevices(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(true);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->expects($this->never())->method('cancelAlert');

        $this->expectException(AccessDeniedHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);
    }

    private function buildAlertMock(): FallAlert&MockObject
    {
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getClientAlertId')->willReturn('client-001');
        $alert->method('getStatus')->willReturn(FallAlertStatus::Cancelled);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getCancelledAt')->willReturn(new DateTimeImmutable());

        return $alert;
    }
}
