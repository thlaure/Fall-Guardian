<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Domain\Device\Processor\DeviceRegistrationProcessor;
use App\Domain\Device\Request\DeviceRegistrationInputDTO;
use App\Domain\Device\Service\DeviceRegistrationService;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceTokenHasher;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class DeviceRegistrationProcessorTest extends TestCase
{
    private DeviceRepositoryInterface&MockObject $deviceRepository;

    private EndpointRateLimiterInterface&MockObject $rateLimiter;

    private DeviceRegistrationProcessor $processor;

    protected function setUp(): void
    {
        $this->deviceRepository = $this->createMock(DeviceRepositoryInterface::class);
        $this->rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $service = new DeviceRegistrationService(new DeviceTokenHasher('test-secret'), $this->deviceRepository);
        $this->processor = new DeviceRegistrationProcessor($service, $this->rateLimiter);
    }

    #[Test]
    public function itDelegatesToServiceAndReturnsDTO(): void
    {
        $savedDevice = null;
        $this->deviceRepository
            ->expects($this->once())
            ->method('save')
            ->with($this->callback(static function (Device $device) use (&$savedDevice): bool {
                $savedDevice = $device;

                return true;
            }));
        $this->rateLimiter->expects($this->once())->method('consume')->with('device_registration', 20, 60);

        $data = new DeviceRegistrationInputDTO();
        $data->platform = 'ios';
        $data->appVersion = '1.0.0';
        $data->deviceType = 'protected_person';

        $result = $this->processor->process($data, $this->createMock(Operation::class));

        $this->assertInstanceOf(Device::class, $savedDevice);
        $this->assertSame($savedDevice->getPublicId(), $result->deviceId);
        $this->assertSame('ios', $savedDevice->getPlatform());
        $this->assertSame('1.0.0', $savedDevice->getAppVersion());
        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $result->deviceToken);
    }
}
