<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Provider\FallAlertProvider;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Uid\Uuid;

final class FallAlertProviderTest extends TestCase
{
    private AlertIngestionServiceInterface&MockObject $alertIngestionService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private FallAlertProvider $provider;

    protected function setUp(): void
    {
        $this->alertIngestionService = $this->createMock(AlertIngestionServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->provider = new FallAlertProvider($this->alertIngestionService, $this->currentDeviceProvider);
    }

    #[Test]
    public function itProvidesAlertOutputDTO(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getClientAlertId')->willReturn('client-001');
        $alert->method('getStatus')->willReturn(FallAlertStatus::Received);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getCancelledAt')->willReturn(null);

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->method('getAlertForDevice')->willReturn($alert);

        $result = $this->provider->provide($this->createMock(Operation::class), ['id' => 'some-uuid']);

        $this->assertSame('client-001', $result->clientAlertId);
    }

    #[Test]
    public function itThrowsNotFoundWhenAlertNotFound(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->method('getAlertForDevice')->willReturn(null);

        $this->expectException(NotFoundHttpException::class);

        $this->provider->provide($this->createMock(Operation::class), ['id' => 'unknown-uuid']);
    }

    #[Test]
    public function itThrowsNotFoundWhenIdMissing(): void
    {
        $this->expectException(NotFoundHttpException::class);

        $this->provider->provide($this->createMock(Operation::class), []);
    }
}
