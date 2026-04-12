<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\Alert\Handler\SendFallAlertPushMessageHandler;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Message\SendFallAlertPushMessage;
use DateTimeImmutable;
use Doctrine\ORM\EntityManagerInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Uid\Uuid;

final class SendFallAlertPushMessageHandlerTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $fallAlertRepository;

    private CaregiverLinkRepositoryInterface&MockObject $linkRepository;

    private CaregiverPushTokenRepositoryInterface&MockObject $pushTokenRepository;

    private PushGatewayInterface&MockObject $pushGateway;

    private EntityManagerInterface&MockObject $entityManager;

    private SendFallAlertPushMessageHandler $handler;

    protected function setUp(): void
    {
        $this->fallAlertRepository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->linkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->pushTokenRepository = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $this->pushGateway = $this->createMock(PushGatewayInterface::class);
        $this->entityManager = $this->createMock(EntityManagerInterface::class);

        $this->handler = new SendFallAlertPushMessageHandler(
            $this->fallAlertRepository,
            $this->linkRepository,
            $this->pushTokenRepository,
            $this->pushGateway,
            $this->entityManager,
        );
    }

    #[Test]
    public function itSkipsUnknownAlert(): void
    {
        $this->fallAlertRepository->method('findById')->willReturn(null);
        $this->pushGateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertPushMessage('unknown-id'));
    }

    #[Test]
    public function itSkipsCancelledAlert(): void
    {
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(new DateTimeImmutable());
        $this->fallAlertRepository->method('findById')->willReturn($alert);

        $this->pushGateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }

    #[Test]
    public function itSkipsWhenNoActiveLinks(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(null);
        $alert->method('getDevice')->willReturn($device);

        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([]);

        $this->pushGateway->expects($this->never())->method('send');
        $this->entityManager->expects($this->never())->method('flush');

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }

    #[Test]
    public function itSendsPushToAllCaregiverDevicesWithTokens(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('getId')->willReturn(Uuid::v7());

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiverDevice);

        $pushToken = $this->createMock(CaregiverPushToken::class);
        $pushToken->method('getFcmToken')->willReturn('fcm-token-abc');

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(null);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable('2025-01-01T12:00:00+00:00'));
        $alert->method('getLatitude')->willReturn(null);
        $alert->method('getLongitude')->willReturn(null);

        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);
        $this->pushTokenRepository->method('findByDevice')->with($caregiverDevice)->willReturn($pushToken);
        $this->pushGateway->method('getProviderName')->willReturn('fake');
        $this->pushGateway->expects($this->once())->method('send')->willReturn(['providerMessageId' => 'push-001']);

        $alert->expects($this->once())->method('addPushAttempt');
        $this->entityManager->expects($this->once())->method('persist');
        $this->entityManager->expects($this->once())->method('flush');

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }

    #[Test]
    public function itSkipsCaregiverWithNoToken(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);

        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiverDevice);

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(null);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());

        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);
        $this->pushTokenRepository->method('findByDevice')->willReturn(null);

        $this->pushGateway->expects($this->never())->method('send');
        $this->entityManager->expects($this->once())->method('flush');

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }
}
