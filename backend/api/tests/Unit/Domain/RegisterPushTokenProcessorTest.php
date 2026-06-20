<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Caregiver\Processor\RegisterPushTokenProcessor;
use App\Domain\Caregiver\Request\RegisterPushTokenInputDTO;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

final class RegisterPushTokenProcessorTest extends TestCase
{
    private InviteServiceInterface&MockObject $inviteService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private RegisterPushTokenProcessor $processor;

    protected function setUp(): void
    {
        $this->inviteService = $this->createMock(InviteServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->processor = new RegisterPushTokenProcessor($this->inviteService, $this->currentDeviceProvider);
    }

    #[Test]
    public function itRegistersPushTokenAndReturnsNull(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->inviteService->method('registerPushToken')->willReturn($this->createMock(CaregiverPushToken::class));

        $data = new RegisterPushTokenInputDTO();
        $data->fcmToken = 'fcm-abc';

        $result = $this->processor->process($data, $this->createMock(Operation::class));

        $this->assertNull($result);
    }

    #[Test]
    public function itThrowsUnprocessableWhenDomainViolation(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->inviteService->method('registerPushToken')->willThrowException(new DomainException('Not a caregiver.'));

        $data = new RegisterPushTokenInputDTO();
        $data->fcmToken = 'fcm-abc';

        $this->expectException(UnprocessableEntityHttpException::class);

        $this->processor->process($data, $this->createMock(Operation::class));
    }
}
