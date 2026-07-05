<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Caregiver\Processor\CreateInviteProcessor;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Entity\CaregiverInvite;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DateTimeImmutable;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

final class CreateInviteProcessorTest extends TestCase
{
    private InviteServiceInterface&MockObject $inviteService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private EndpointRateLimiterInterface&MockObject $rateLimiter;

    private CreateInviteProcessor $processor;

    protected function setUp(): void
    {
        $this->inviteService = $this->createMock(InviteServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $this->processor = new CreateInviteProcessor($this->inviteService, $this->currentDeviceProvider, $this->rateLimiter);
    }

    #[Test]
    public function itCreatesInviteAndReturnsDTO(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('device-1');
        $invite = $this->createMock(CaregiverInvite::class);
        $invite->method('getCode')->willReturn('ABCD1234');
        $invite->method('getExpiresAt')->willReturn(new DateTimeImmutable('+30 minutes'));

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->rateLimiter->expects($this->once())->method('consume')->with('invite_create', 10, 300, 'device-1');
        $this->inviteService->method('createInvite')->willReturn($invite);

        $result = $this->processor->process(null, $this->createMock(Operation::class));

        $this->assertSame('ABCD1234', $result->code);
        $this->assertNotEmpty($result->expiresAt);
    }

    #[Test]
    public function itThrowsUnprocessableWhenDomainExceptionRaised(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->inviteService->method('createInvite')->willThrowException(new DomainException('Not allowed.'));

        $this->expectException(UnprocessableEntityHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class));
    }
}
