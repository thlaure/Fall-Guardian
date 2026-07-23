<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\AlertIngestionService;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;

use const DATE_ATOM;

use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\DelayStamp;

final class AlertIngestionServiceTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $repository;

    private MessageBusInterface&MockObject $bus;

    private AlertIngestionService $service;

    private MockClock $clock;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->bus = $this->createMock(MessageBusInterface::class);
        $this->clock = new MockClock('2026-07-23T08:00:00+00:00');
        $this->service = new AlertIngestionService($this->repository, $this->bus, $this->clock);
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

        $alert = $this->service->createAlert($device, 'client-001', new DateTimeImmutable('+1 day'), 'en', null, null);

        self::assertSame('client-001', $alert->getClientAlertId());
        self::assertSame(
            '2026-07-23T08:00:30+00:00',
            $alert->getCancelDeadlineAt()->format(DATE_ATOM),
        );
    }

    #[Test]
    public function itDispatchesPushMessageWithDelayStampMatchingRemainingGrace(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);

        $capturedStamps = null;
        $this->bus->expects($this->once())
            ->method('dispatch')
            ->willReturnCallback(static function (object $msg, array $stamps = []) use (&$capturedStamps): Envelope {
                $capturedStamps = $stamps;

                return new Envelope($msg);
            });

        $this->service->createAlert($device, 'client-001', new DateTimeImmutable('+1 day'), 'en', null, null);

        self::assertNotNull($capturedStamps);
        $delayStamps = array_values(array_filter($capturedStamps, static fn (object $s): bool => $s instanceof DelayStamp));
        self::assertCount(1, $delayStamps);
        self::assertSame(30_000, $delayStamps[0]->getDelay());
    }

    #[Test]
    public function itIgnoresAnOldDeviceTimestampWhenSchedulingTheGracePeriod(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);

        $capturedStamps = null;
        $this->bus->expects($this->once())
            ->method('dispatch')
            ->willReturnCallback(static function (object $msg, array $stamps = []) use (&$capturedStamps): Envelope {
                $capturedStamps = $stamps;

                return new Envelope($msg);
            });

        $longAgo = new DateTimeImmutable()->modify('-1 hour');
        $this->service->createAlert($device, 'client-001', $longAgo, 'en', null, null);

        $delayStamps = array_values(array_filter($capturedStamps, static fn (object $s): bool => $s instanceof DelayStamp));
        self::assertCount(1, $delayStamps);
        self::assertSame(30_000, $delayStamps[0]->getDelay());
    }

    #[Test]
    public function itAttachesLocationToExistingAlert(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->expects($this->once())->method('updateLocation')->with(48.8566, 2.3522);

        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn($alert);
        $this->repository->expects($this->once())->method('save')->with($alert);

        $result = $this->service->attachLocation($device, 'client-001', 48.8566, 2.3522);

        self::assertSame($alert, $result);
    }

    #[Test]
    public function itReturnsNullWhenAttachingLocationToUnknownAlert(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);
        $this->repository->expects($this->never())->method('save');

        $result = $this->service->attachLocation($device, 'unknown', 48.8566, 2.3522);

        self::assertNull($result);
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

        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn($existing);
        $this->repository->expects($this->once())
            ->method('cancelPending')
            ->with($device, 'client-001', $this->clock->now())
            ->willReturn($existing);
        $this->repository->expects($this->never())->method('save');
        $this->bus->expects($this->never())->method('dispatch');

        $result = $this->service->createCancelledAlert($device, 'client-001', new DateTimeImmutable(), 'en', null, null);

        self::assertSame($existing, $result);
    }

    #[Test]
    public function itCancelsAlert(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);

        $this->repository->expects($this->once())
            ->method('cancelPending')
            ->with($device, 'client-001', $this->clock->now())
            ->willReturn($alert);

        $result = $this->service->cancelAlert($device, 'client-001');

        self::assertSame($alert, $result);
    }

    #[Test]
    public function itReturnNullWhenCancellingUnknownAlert(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('cancelPending')->willReturn(null);

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
