<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Processor\ReportAlertReceiptProcessor;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\Uid\Uuid;

final class ReportAlertReceiptProcessorTest extends TestCase
{
    #[Test]
    public function linkedCaregiverCanReportDeliveryReceiptIdempotently(): void
    {
        $clock = new MockClock('2026-07-23T08:00:35+00:00');
        $caregiverId = Uuid::v7();
        $caregiver = $this->createMock(Device::class);
        $caregiver->method('getId')->willReturn($caregiverId);
        $caregiver->method('getPublicId')->willReturn('caregiver-1');
        $protected = $this->createMock(Device::class);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($protected);
        $alert->expects(self::once())->method('markDeliveryReceived')->with($clock->now());

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiver);

        $deviceContext = $this->createMock(DeviceContextInterface::class);
        $deviceContext->method('requireDevice')->willReturn($caregiver);
        $repository = $this->createMock(FallAlertRepositoryInterface::class);
        $repository->method('findById')->with('alert-1')->willReturn($alert);
        $repository->expects(self::once())->method('save')->with($alert);
        $links = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $links->method('findActiveByProtectedDevice')->with($protected)->willReturn([$link]);
        $rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $rateLimiter->expects(self::once())
            ->method('consume')
            ->with('report_alert_receipt', 120, 60, 'caregiver-1');

        $processor = new ReportAlertReceiptProcessor(
            $deviceContext,
            $repository,
            $links,
            $rateLimiter,
            $clock,
        );

        self::assertNull(
            $processor->process(null, $this->createMock(Operation::class), ['id' => 'alert-1']),
        );
    }

    #[Test]
    public function unlinkedCaregiverCannotReportDeliveryReceipt(): void
    {
        $caregiver = $this->createMock(Device::class);
        $caregiver->method('getId')->willReturn(Uuid::v7());
        $protected = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($protected);
        $otherCaregiver = $this->createMock(Device::class);
        $otherCaregiver->method('getId')->willReturn(Uuid::v7());
        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($otherCaregiver);

        $deviceContext = $this->createMock(DeviceContextInterface::class);
        $deviceContext->method('requireDevice')->willReturn($caregiver);
        $repository = $this->createMock(FallAlertRepositoryInterface::class);
        $repository->method('findById')->willReturn($alert);
        $links = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $links->method('findActiveByProtectedDevice')->willReturn([$link]);

        $processor = new ReportAlertReceiptProcessor(
            $deviceContext,
            $repository,
            $links,
            $this->createMock(EndpointRateLimiterInterface::class),
            new MockClock(),
        );

        $this->expectException(AccessDeniedHttpException::class);
        $processor->process(null, $this->createMock(Operation::class), ['id' => 'alert-1']);
    }
}
