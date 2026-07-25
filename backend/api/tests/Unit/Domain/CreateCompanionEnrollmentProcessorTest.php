<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Post;
use App\Domain\Companion\Processor\CreateCompanionEnrollmentProcessor;
use App\Domain\Companion\Request\CreateCompanionEnrollmentInputDTO;
use App\Domain\Companion\Service\CompanionEnrollmentServiceInterface;
use App\Entity\CompanionEnrollment;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DateTimeImmutable;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

final class CreateCompanionEnrollmentProcessorTest extends TestCase
{
    #[Test]
    public function itCreatesEnrollmentForAuthenticatedProtectedDevice(): void
    {
        $service = $this->createMock(CompanionEnrollmentServiceInterface::class);
        $deviceContext = $this->createMock(DeviceContextInterface::class);
        $rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('protected-device');
        $deviceContext->method('requireDevice')->willReturn($device);

        $expiresAt = new DateTimeImmutable('2026-07-25T10:05:00+00:00');
        $enrollment = $this->createMock(CompanionEnrollment::class);
        $enrollment->method('getExpiresAt')->willReturn($expiresAt);
        $service->expects($this->once())
            ->method('create')
            ->with($device, 'watchos')
            ->willReturn(['token' => str_repeat('a', 64), 'enrollment' => $enrollment]);
        $rateLimiter->expects($this->once())
            ->method('consume')
            ->with('companion_enrollment_create', 5, 300, 'protected-device');

        $input = new CreateCompanionEnrollmentInputDTO();
        $input->platform = 'watchos';
        $processor = new CreateCompanionEnrollmentProcessor($service, $deviceContext, $rateLimiter);

        $output = $processor->process($input, new Post());

        self::assertSame(str_repeat('a', 64), $output->enrollmentToken);
        self::assertSame('2026-07-25T10:05:00+00:00', $output->expiresAt);
    }

    #[Test]
    public function itMapsDomainFailureToUnprocessableEntity(): void
    {
        $service = $this->createMock(CompanionEnrollmentServiceInterface::class);
        $deviceContext = $this->createMock(DeviceContextInterface::class);
        $rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $device = $this->createMock(Device::class);
        $device->method('getPublicId')->willReturn('caregiver-device');
        $deviceContext->method('requireDevice')->willReturn($device);
        $service->method('create')->willThrowException(new DomainException('Not allowed.'));

        $input = new CreateCompanionEnrollmentInputDTO();
        $input->platform = 'watchos';

        $this->expectException(UnprocessableEntityHttpException::class);
        new CreateCompanionEnrollmentProcessor($service, $deviceContext, $rateLimiter)
            ->process($input, new Post());
    }
}
