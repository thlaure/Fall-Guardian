<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Handler\SendFallAlertPushMessageHandler;
use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Entity\FallAlert;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Uid\Uuid;

final class SendFallAlertPushMessageHandlerTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $fallAlertRepository;

    private CaregiverLinkRepositoryInterface&MockObject $linkRepository;

    private CaregiverPushTokenRepositoryInterface&MockObject $pushTokenRepository;

    private PushGatewayInterface&MockObject $pushGateway;

    private SendFallAlertPushMessageHandler $handler;

    private MockClock $clock;

    protected function setUp(): void
    {
        $this->fallAlertRepository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->linkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->pushTokenRepository = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $this->pushGateway = $this->createMock(PushGatewayInterface::class);
        $this->clock = new MockClock('2026-07-23T08:00:31+00:00');

        $this->handler = new SendFallAlertPushMessageHandler(
            $this->fallAlertRepository,
            $this->linkRepository,
            $this->pushTokenRepository,
            $this->pushGateway,
            $this->clock,
        );
    }

    #[Test]
    public function itSkipsUnknownAlert(): void
    {
        $this->fallAlertRepository->method('claimForDispatch')->willReturn(null);
        $this->pushGateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertPushMessage('unknown-id'));
    }

    #[Test]
    public function itSkipsAnAlertThatCannotBeClaimedForDispatch(): void
    {
        $this->fallAlertRepository->method('claimForDispatch')->willReturn(null);

        $this->pushGateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }

    #[Test]
    public function itSkipsWhenNoActiveLinks(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($device);

        $this->fallAlertRepository->method('claimForDispatch')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([]);

        $this->pushGateway->expects($this->never())->method('send');
        $alert->expects($this->once())->method('markFailed');
        $this->fallAlertRepository->expects($this->once())->method('save')->with($alert);

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
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable('2025-01-01T12:00:00+00:00'));
        $alert->method('getLatitude')->willReturn(null);
        $alert->method('getLongitude')->willReturn(null);

        $this->fallAlertRepository->method('claimForDispatch')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);
        $this->pushTokenRepository->method('findByDevice')->with($caregiverDevice)->willReturn($pushToken);
        $this->pushGateway->method('getProviderName')->willReturn('fake');
        $this->pushGateway->expects($this->once())->method('send')->willReturn(['providerMessageId' => 'push-001']);

        $alert->expects($this->once())->method('addPushAttempt');
        $alert->expects($this->once())->method('markSent');
        $this->fallAlertRepository->expects($this->once())->method('save')->with($alert);

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }

    #[Test]
    public function itSendsPushToEveryLinkedCaregiverDeviceWithAToken(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $firstCaregiverDevice = $this->createMock(Device::class);
        $secondCaregiverDevice = $this->createMock(Device::class);

        $firstLink = $this->createMock(CaregiverLink::class);
        $firstLink->method('getCaregiverDevice')->willReturn($firstCaregiverDevice);

        $secondLink = $this->createMock(CaregiverLink::class);
        $secondLink->method('getCaregiverDevice')->willReturn($secondCaregiverDevice);

        $firstPushToken = $this->createMock(CaregiverPushToken::class);
        $firstPushToken->method('getFcmToken')->willReturn('first-fcm-token');

        $secondPushToken = $this->createMock(CaregiverPushToken::class);
        $secondPushToken->method('getFcmToken')->willReturn('second-fcm-token');

        $alert = $this->createMock(FallAlert::class);
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->method('getId')->willReturn(Uuid::v7());
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable('2025-01-01T12:00:00+00:00'));
        $alert->method('getLatitude')->willReturn(48.8566);
        $alert->method('getLongitude')->willReturn(2.3522);

        $this->fallAlertRepository->method('claimForDispatch')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([$firstLink, $secondLink]);
        $this->pushTokenRepository
            ->expects($this->exactly(2))
            ->method('findByDevice')
            ->willReturnCallback(
                static fn (Device $device): ?CaregiverPushToken => match ($device) {
                    $firstCaregiverDevice => $firstPushToken,
                    $secondCaregiverDevice => $secondPushToken,
                    default => null,
                },
            );
        $this->pushGateway->method('getProviderName')->willReturn('fake');
        $this->pushGateway
            ->expects($this->exactly(2))
            ->method('send')
            ->willReturn(['providerMessageId' => 'push-id']);

        $alert->expects($this->exactly(2))->method('addPushAttempt');
        $alert->expects($this->once())->method('markSent');
        $this->fallAlertRepository->expects($this->once())->method('save')->with($alert);

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
        $alert->method('getDevice')->willReturn($protectedDevice);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());

        $this->fallAlertRepository->method('claimForDispatch')->willReturn($alert);
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([$link]);
        $this->pushTokenRepository->method('findByDevice')->willReturn(null);

        $this->pushGateway->expects($this->never())->method('send');
        $alert->expects($this->once())->method('markFailed');
        $this->fallAlertRepository->expects($this->once())->method('save')->with($alert);

        ($this->handler)(new SendFallAlertPushMessage('some-id'));
    }
}
