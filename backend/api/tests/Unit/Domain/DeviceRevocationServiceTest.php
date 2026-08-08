<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Domain\Device\Service\DeviceRevocationService;
use App\Entity\Device;
use App\Entity\ProtectedPerson;
use App\Enum\DeviceType;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class DeviceRevocationServiceTest extends TestCase
{
    private DeviceRepositoryInterface&MockObject $repository;

    private DeviceRevocationService $service;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(DeviceRepositoryInterface::class);
        $this->service = new DeviceRevocationService($this->repository);
    }

    #[Test]
    public function itRevokesTheAuthenticatedDevice(): void
    {
        $device = new Device('phone', 'phone-hash', 'ios', '1.0.0');

        $this->repository->expects($this->once())->method('findByPublicId')->with('phone')->willReturn($device);
        $this->repository->expects($this->once())->method('save')->with($device);

        $this->service->revoke($device, 'phone');

        self::assertTrue($device->isRevoked());
    }

    #[Test]
    public function itRevokesACompanionForTheSameProtectedPerson(): void
    {
        $phone = new Device('phone', 'phone-hash', 'ios', '1.0.0');
        $watch = new Device('watch', 'watch-hash', 'watchos', '1.0.0');
        $watch->attachToProtectedPerson($phone->getProtectedPerson() ?? new ProtectedPerson());

        $this->repository->expects($this->once())->method('findByPublicId')->with('watch')->willReturn($watch);
        $this->repository->expects($this->once())->method('save')->with($watch);

        $this->service->revoke($phone, 'watch');

        self::assertTrue($watch->isRevoked());
    }

    #[Test]
    public function itRejectsRevocationOfAnUnrelatedDevice(): void
    {
        $phone = new Device('phone', 'phone-hash', 'ios', '1.0.0');
        $otherPhone = new Device('other-phone', 'other-hash', 'ios', '1.0.0');

        $this->repository->expects($this->once())->method('findByPublicId')->with('other-phone')->willReturn($otherPhone);
        $this->repository->expects($this->never())->method('save');

        $this->expectException(DomainException::class);
        $this->expectExceptionMessage('This device cannot revoke the requested device.');

        $this->service->revoke($phone, 'other-phone');
    }

    #[Test]
    public function itPreventsACaregiverFromRevokingAnotherDevice(): void
    {
        $caregiver = new Device('caregiver', 'caregiver-hash', 'android', '1.0.0');
        $caregiver->setDeviceType(DeviceType::Caregiver);
        $phone = new Device('phone', 'phone-hash', 'ios', '1.0.0');

        $this->repository->expects($this->once())->method('findByPublicId')->with('phone')->willReturn($phone);
        $this->repository->expects($this->never())->method('save');

        $this->expectException(DomainException::class);

        $this->service->revoke($caregiver, 'phone');
    }
}
