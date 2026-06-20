<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\AlertIngestionService;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;

final class AlertIngestionServiceTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $repository;

    private MessageBusInterface&MockObject $bus;

    private AlertIngestionService $service;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->bus = $this->createMock(MessageBusInterface::class);
        $this->service = new AlertIngestionService($this->repository, $this->bus);
    }

    #[Test]
    public function itCreatesAlertAndDispatchesPushMessage(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);
        $this->repository->expects($this->once())->method('save');

        $this->bus->expects($this->once())
            ->method('dispatch')
            ->willReturnCallback(static fn (object $msg): Envelope => new Envelope($msg));

        $alert = $this->service->createAlert($device, 'client-001', new DateTimeImmutable(), 'en', null, null);

        self::assertSame('client-001', $alert->getClientAlertId());
    }

    #[Test]
    public function itReturnsExistingAlertIdempotently(): void
    {
        $device = $this->createMock(Device::class);
        $existing = $this->createMock(FallAlert::class);

        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn($existing);
        $this->repository->expects($this->never())->method('save');
        $this->bus->expects($this->never())->method('dispatch');

        $result = $this->service->createAlert($device, 'client-001', new DateTimeImmutable(), 'en', null, null);

        self::assertSame($existing, $result);
    }

    #[Test]
    public function itCreatesCancelledAlertWithoutDispatchingPushMessage(): void
    {
        $device = new Device('device-1', 'hash', 'android', '1.0.0');
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);
        $this->repository->expects($this->once())->method('save');
        $this->bus->expects($this->never())->method('dispatch');

        $alert = $this->service->createCancelledAlert(
            $device,
            'client-cancelled-001',
            new DateTimeImmutable(),
            'en',
            null,
            null,
        );

        self::assertSame('client-cancelled-001', $alert->getClientAlertId());
        self::assertSame(FallAlertStatus::Cancelled, $alert->getStatus());
        self::assertInstanceOf(DateTimeImmutable::class, $alert->getCancelledAt());
    }

    #[Test]
    public function itCancelsExistingAlertWhenCreatingCancelledAlertIdempotently(): void
    {
        $device = $this->createMock(Device::class);
        $existing = $this->createMock(FallAlert::class);
        $existing->method('getStatus')->willReturn(FallAlertStatus::Received);
        $existing->expects($this->once())->method('cancel');

        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn($existing);
        $this->repository->expects($this->once())->method('save')->with($existing);
        $this->bus->expects($this->never())->method('dispatch');

        $result = $this->service->createCancelledAlert($device, 'client-001', new DateTimeImmutable(), 'en', null, null);

        self::assertSame($existing, $result);
    }

    #[Test]
    public function itCancelsAlert(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->expects($this->once())->method('cancel');

        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn($alert);
        $this->repository->expects($this->once())->method('save')->with($alert);

        $result = $this->service->cancelAlert($device, 'client-001');

        self::assertSame($alert, $result);
    }

    #[Test]
    public function itReturnNullWhenCancellingUnknownAlert(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);

        $result = $this->service->cancelAlert($device, 'unknown');

        self::assertNull($result);
    }

    #[Test]
    public function itReturnsAlertForMatchingDevice(): void
    {
        $uuid = \Symfony\Component\Uid\Uuid::v7();
        $device = $this->createMock(Device::class);
        $device->method('getId')->willReturn($uuid);

        $alert = $this->createMock(FallAlert::class);
        $alertDevice = $this->createMock(Device::class);
        $alertDevice->method('getId')->willReturn($uuid);
        $alert->method('getDevice')->willReturn($alertDevice);

        $this->repository->method('findById')->willReturn($alert);

        $result = $this->service->getAlertForDevice($device, 'some-id');

        self::assertSame($alert, $result);
    }

    #[Test]
    public function itReturnsNullWhenAlertBelongsToDifferentDevice(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getId')->willReturn(\Symfony\Component\Uid\Uuid::v7());

        $alert = $this->createMock(FallAlert::class);
        $alertDevice = $this->createMock(Device::class);
        $alertDevice->method('getId')->willReturn(\Symfony\Component\Uid\Uuid::v7());
        $alert->method('getDevice')->willReturn($alertDevice);

        $this->repository->method('findById')->willReturn($alert);

        $result = $this->service->getAlertForDevice($device, 'some-id');

        self::assertNull($result);
    }

    #[Test]
    public function itReturnsNullWhenAlertNotFound(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findById')->willReturn(null);

        $result = $this->service->getAlertForDevice($device, 'unknown');

        self::assertNull($result);
    }
}
