<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\Alert\Handler\AlertIngestionService;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
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
    public function itCreatesAlertAndDispatchesBothMessages(): void
    {
        $device = $this->createMock(Device::class);
        $this->repository->method('findOneByDeviceAndClientAlertId')->willReturn(null);
        $this->repository->expects($this->once())->method('save');

        $this->bus->expects($this->exactly(2))
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
}
