<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Caregiver\Port\CaregiverInviteRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Caregiver\Service\InviteService;
use App\Entity\CaregiverInvite;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use RuntimeException;

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
        self::assertSame(32, strlen($invite->getCode()));
        self::assertMatchesRegularExpression('/^[A-F0-9]{32}$/', $invite->getCode());
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

    #[Test]
    public function itReactivatesExistingRevokedLink(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(true);

        $invite = $this->createMock(CaregiverInvite::class);
        $invite->method('getDevice')->willReturn($protectedDevice);
        $invite->expects($this->once())->method('markUsed');

        $existing = $this->createMock(CaregiverLink::class);
        $existing->method('getStatus')->willReturn(\App\Enum\CaregiverLinkStatus::Revoked);
        $existing->expects($this->once())->method('reactivate');

        $this->inviteRepository->method('findActiveByCode')->willReturn($invite);
        $this->linkRepository->method('findExistingPair')->willReturn($existing);
        $this->inviteRepository->expects($this->once())->method('save')->with($invite);
        $this->linkRepository->expects($this->once())->method('save')->with($existing);

        $result = $this->service->acceptInvite('ABCD1234', $caregiverDevice);

        $this->assertSame($existing, $result);
    }

    #[Test]
    public function itReturnsExistingActiveLinkWithoutCreatingNew(): void
    {
        $protectedDevice = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);
        $caregiverDevice->method('isCaregiver')->willReturn(true);

        $invite = $this->createMock(CaregiverInvite::class);
        $invite->method('getDevice')->willReturn($protectedDevice);
        $invite->expects($this->once())->method('markUsed');

        $existing = $this->createMock(CaregiverLink::class);
        $existing->method('getStatus')->willReturn(\App\Enum\CaregiverLinkStatus::Active);

        $this->inviteRepository->method('findActiveByCode')->willReturn($invite);
        $this->linkRepository->method('findExistingPair')->willReturn($existing);
        $this->inviteRepository->expects($this->once())->method('save');
        $this->linkRepository->expects($this->never())->method('save');

        $result = $this->service->acceptInvite('ABCD1234', $caregiverDevice);

        $this->assertSame($existing, $result);
    }
}
