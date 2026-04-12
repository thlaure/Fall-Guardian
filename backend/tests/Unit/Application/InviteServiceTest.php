<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\Caregiver\Handler\InviteService;
use App\Domain\Caregiver\Port\CaregiverInviteRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Entity\CaregiverInvite;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use RuntimeException;

use function strlen;

final class InviteServiceTest extends TestCase
{
    private CaregiverInviteRepositoryInterface&MockObject $inviteRepository;

    private CaregiverLinkRepositoryInterface&MockObject $linkRepository;

    private CaregiverPushTokenRepositoryInterface&MockObject $pushTokenRepository;

    private InviteService $service;

    protected function setUp(): void
    {
        $this->inviteRepository = $this->createMock(CaregiverInviteRepositoryInterface::class);
        $this->linkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->pushTokenRepository = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $this->service = new InviteService(
            $this->inviteRepository,
            $this->linkRepository,
            $this->pushTokenRepository,
        );
    }

    #[Test]
    public function itCreatesInviteForProtectedPersonDevice(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(false);
        $this->inviteRepository->expects($this->once())->method('save');

        $invite = $this->service->createInvite($device);

        self::assertInstanceOf(CaregiverInvite::class, $invite);
        self::assertSame(8, strlen($invite->getCode()));
    }

    #[Test]
    public function itRejectsCaregiverDeviceCreatingInvite(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(true);

        $this->expectException(DomainException::class);
        $this->service->createInvite($device);
    }

    #[Test]
    public function itAcceptsInviteAndCreatesLink(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(true);

        $invite = $this->createMock(CaregiverInvite::class);
        $invite->method('getDevice')->willReturn($protectedDevice);
        $invite->expects($this->once())->method('markUsed');

        $this->inviteRepository->method('findActiveByCode')->with('ABCD1234')->willReturn($invite);
        $this->linkRepository->method('findExistingPair')->willReturn(null);
        $this->inviteRepository->expects($this->once())->method('save');
        $this->linkRepository->expects($this->once())->method('save');

        $link = $this->service->acceptInvite('ABCD1234', $caregiverDevice);

        self::assertInstanceOf(CaregiverLink::class, $link);
    }

    #[Test]
    public function itRejectsProtectedPersonAcceptingInvite(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(false);

        $this->expectException(DomainException::class);
        $this->service->acceptInvite('ABCD1234', $caregiverDevice);
    }

    #[Test]
    public function itRejectsExpiredOrUnknownInviteCode(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(true);
        $this->inviteRepository->method('findActiveByCode')->willReturn(null);

        $this->expectException(RuntimeException::class);
        $this->service->acceptInvite('BADCODE', $caregiverDevice);
    }

    #[Test]
    public function itRegistersNewPushToken(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(true);

        $this->pushTokenRepository->method('findByDevice')->willReturn(null);
        $this->pushTokenRepository->expects($this->once())->method('save');

        $token = $this->service->registerPushToken($caregiverDevice, 'fcm-token-xyz');

        self::assertInstanceOf(CaregiverPushToken::class, $token);
        self::assertSame('fcm-token-xyz', $token->getFcmToken());
    }

    #[Test]
    public function itUpdatesExistingPushToken(): void
    {
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(true);

        $existing = $this->createMock(CaregiverPushToken::class);
        $existing->expects($this->once())->method('update')->with('new-token');
        $existing->method('getFcmToken')->willReturn('new-token');

        $this->pushTokenRepository->method('findByDevice')->willReturn($existing);
        $this->pushTokenRepository->expects($this->once())->method('save');

        $token = $this->service->registerPushToken($caregiverDevice, 'new-token');

        self::assertSame($existing, $token);
    }

    #[Test]
    public function itRejectsPushTokenForNonCaregiverDevice(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(false);

        $this->expectException(DomainException::class);
        $this->service->registerPushToken($device, 'fcm-token');
    }
}
