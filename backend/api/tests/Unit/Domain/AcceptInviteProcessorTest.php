<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Caregiver\Processor\AcceptInviteProcessor;
use App\Domain\Caregiver\Request\AcceptInviteInputDTO;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use RuntimeException;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

final class AcceptInviteProcessorTest extends TestCase
{
    private InviteServiceInterface&MockObject $inviteService;

    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private EndpointRateLimiterInterface&MockObject $rateLimiter;

    private RequestStack $requestStack;

    private AcceptInviteProcessor $processor;

    protected function setUp(): void
    {
        $this->inviteService = $this->createMock(InviteServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $this->requestStack = new RequestStack();
        $this->processor = new AcceptInviteProcessor($this->inviteService, $this->currentDeviceProvider, $this->rateLimiter, $this->requestStack);
    }

    #[Test]
    public function itAcceptsInviteAndReturnsNull(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('caregiver-1');
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->rateLimiter->expects($this->once())->method('consume')->with('invite_accept', 5, 600, 'caregiver-1');
        $this->inviteService->expects($this->once())
            ->method('acceptInvite')
            ->with('ABCD1234', $device, 'Marie', 'Thomas')
            ->willReturn($this->createMock(CaregiverLink::class));

        $result = $this->processor->process($this->acceptInviteInput('Marie', 'Thomas'), $this->createMock(Operation::class), ['code' => 'ABCD1234']);

        $this->assertNull($result);
    }

    #[Test]
    public function itFallsBackToRawJsonWhenApiPlatformDropsCaregiverName(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('caregiver-1');
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->requestStack->push(new Request(content: '{"protectedPersonName":"Truc","caregiverName":"Toto"}'));

        $this->inviteService->expects($this->once())
            ->method('acceptInvite')
            ->with('ABCD1234', $device, 'Truc', 'Toto')
            ->willReturn($this->createMock(CaregiverLink::class));

        $this->processor->process($this->acceptInviteInput('Truc'), $this->createMock(Operation::class), ['code' => 'ABCD1234']);
    }

    #[Test]
    public function itThrowsNotFoundWhenInviteNotFound(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->inviteService->method('acceptInvite')->willThrowException(new RuntimeException('Not found.'));

        $this->expectException(NotFoundHttpException::class);

        $this->processor->process($this->acceptInviteInput('Marie'), $this->createMock(Operation::class), ['code' => 'BADCODE']);
    }

    #[Test]
    public function itThrowsUnprocessableWhenDomainViolation(): void
    {
        $device = $this->createMock(Device::class);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->inviteService->method('acceptInvite')->willThrowException(new DomainException('Revoked.'));

        $this->expectException(UnprocessableEntityHttpException::class);

        $this->processor->process($this->acceptInviteInput('Marie'), $this->createMock(Operation::class), ['code' => 'ABCD1234']);
    }

    private function acceptInviteInput(string $protectedPersonName, ?string $caregiverName = null): AcceptInviteInputDTO
    {
        $input = new AcceptInviteInputDTO();
        $input->protectedPersonName = $protectedPersonName;
        $input->caregiverName = $caregiverName;

        return $input;
    }
}
