<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Domain\Device\Service\DeviceRegistrationService;
use App\Enum\DeviceType;
use App\Infrastructure\Http\Security\DeviceTokenHasher;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class DeviceRegistrationServiceTest extends TestCase
{
    private DeviceRepositoryInterface&MockObject $repository;

    private DeviceRegistrationService $service;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(DeviceRepositoryInterface::class);
        // DeviceTokenHasher is final — use the real instance (pure, no I/O)
        $this->service = new DeviceRegistrationService(new DeviceTokenHasher('test-secret'), $this->repository);
    }

    #[Test]
    public function itRegistersAProtectedPersonDeviceByDefault(): void
    {
        $this->repository->expects($this->once())->method('save');

        $result = $this->service->register('ios', '1.0.0');

        self::assertInstanceOf(DeviceRegistrationOutputDTO::class, $result);
        self::assertIsString($result->deviceId);
        self::assertNotEmpty($result->deviceToken);
    }

    #[Test]
    public function itRegistersACaregiverDevice(): void
    {
        $this->repository->expects($this->once())->method('save');

        $result = $this->service->register('android', '1.0.0', DeviceType::Caregiver);

        self::assertInstanceOf(DeviceRegistrationOutputDTO::class, $result);
        self::assertIsString($result->deviceId);
        self::assertNotEmpty($result->deviceToken);
    }
}
