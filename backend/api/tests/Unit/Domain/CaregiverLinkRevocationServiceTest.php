<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Caregiver\Service\CaregiverLinkRevocationService;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use RuntimeException;

final class CaregiverLinkRevocationServiceTest extends TestCase
{
    private CaregiverLinkRepositoryInterface&MockObject $linkRepository;

    private CaregiverPushTokenRepositoryInterface&MockObject $pushTokenRepository;

    private PushGatewayInterface&MockObject $pushGateway;

    private CaregiverLinkRevocationService $service;

    protected function setUp(): void
    {
        $this->linkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->pushTokenRepository = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $this->pushGateway = $this->createMock(PushGatewayInterface::class);
        $this->service = new CaregiverLinkRevocationService(
            $this->linkRepository,
            $this->pushTokenRepository,
            $this->pushGateway,
        );
    }

    #[Test]
    public function itRevokesTheLinkAndNotifiesTheCaregiver(): void
    {
        $protectedDevice = new Device('protected', 'protected-hash', 'ios', '1.0.0');
        $caregiverDevice = new Device('caregiver', 'caregiver-hash', 'android', '1.0.0');
        $link = new CaregiverLink($protectedDevice, $caregiverDevice);
        $token = new CaregiverPushToken($caregiverDevice, 'fcm-token');

        $this->linkRepository->expects($this->once())
            ->method('findActiveByIdAndProtectedDevice')
            ->with($link->getId()->toRfc4122(), $protectedDevice)
            ->willReturn($link);
        $this->linkRepository->expects($this->once())->method('save')->with($link);
        $this->pushTokenRepository->expects($this->once())
            ->method('findByDevice')
            ->with($caregiverDevice)
            ->willReturn($token);
        $this->pushGateway->expects($this->once())->method('sendLinkRevoked')->with('fcm-token');

        $this->service->revoke($protectedDevice, $link->getId()->toRfc4122());

        self::assertFalse($link->isActive());
    }

    #[Test]
    public function itThrowsWhenTheLinkIsNotFound(): void
    {
        $protectedDevice = new Device('protected', 'protected-hash', 'ios', '1.0.0');

        $this->linkRepository->expects($this->once())
            ->method('findActiveByIdAndProtectedDevice')
            ->willReturn(null);
        $this->linkRepository->expects($this->never())->method('save');

        $this->expectException(RuntimeException::class);

        $this->service->revoke($protectedDevice, 'unknown-link');
    }

    #[Test]
    public function itRevokesTheLinkEvenWhenThereIsNoPushTokenToNotify(): void
    {
        $protectedDevice = new Device('protected', 'protected-hash', 'ios', '1.0.0');
        $caregiverDevice = new Device('caregiver', 'caregiver-hash', 'android', '1.0.0');
        $link = new CaregiverLink($protectedDevice, $caregiverDevice);

        $this->linkRepository->method('findActiveByIdAndProtectedDevice')->willReturn($link);
        $this->pushTokenRepository->method('findByDevice')->willReturn(null);
        $this->pushGateway->expects($this->never())->method('sendLinkRevoked');

        $this->service->revoke($protectedDevice, $link->getId()->toRfc4122());

        self::assertFalse($link->isActive());
    }

    #[Test]
    public function itKeepsTheLinkRevokedEvenWhenThePushNoticeFails(): void
    {
        $protectedDevice = new Device('protected', 'protected-hash', 'ios', '1.0.0');
        $caregiverDevice = new Device('caregiver', 'caregiver-hash', 'android', '1.0.0');
        $link = new CaregiverLink($protectedDevice, $caregiverDevice);
        $token = new CaregiverPushToken($caregiverDevice, 'fcm-token');

        $this->linkRepository->method('findActiveByIdAndProtectedDevice')->willReturn($link);
        $this->linkRepository->expects($this->once())->method('save')->with($link);
        $this->pushTokenRepository->method('findByDevice')->willReturn($token);
        $this->pushGateway->method('sendLinkRevoked')->willThrowException(new RuntimeException('FCM unavailable'));

        $this->service->revoke($protectedDevice, $link->getId()->toRfc4122());

        self::assertFalse($link->isActive());
    }
}
