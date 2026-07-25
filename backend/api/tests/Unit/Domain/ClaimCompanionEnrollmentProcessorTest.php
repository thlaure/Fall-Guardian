<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Post;
use App\Domain\Companion\Processor\ClaimCompanionEnrollmentProcessor;
use App\Domain\Companion\Request\ClaimCompanionEnrollmentInputDTO;
use App\Domain\Companion\Service\CompanionEnrollmentServiceInterface;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

final class ClaimCompanionEnrollmentProcessorTest extends TestCase
{
    #[Test]
    public function itClaimsEnrollmentAndRateLimitsByClientAddress(): void
    {
        $service = $this->createMock(CompanionEnrollmentServiceInterface::class);
        $rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $token = str_repeat('a', 64);
        $expected = new DeviceRegistrationOutputDTO('watch-id', 'watch-token');
        $service->expects($this->once())
            ->method('claim')
            ->with($token, 'watchos', '1.0.0')
            ->willReturn($expected);
        $rateLimiter->expects($this->once())
            ->method('consume')
            ->with('companion_enrollment_claim', 10, 300);

        $input = new ClaimCompanionEnrollmentInputDTO();
        $input->enrollmentToken = $token;
        $input->platform = 'watchos';
        $input->appVersion = '1.0.0';

        $output = new ClaimCompanionEnrollmentProcessor($service, $rateLimiter)
            ->process($input, new Post());

        self::assertSame($expected, $output);
    }

    #[Test]
    public function itHidesInvalidEnrollmentAsNotFound(): void
    {
        $service = $this->createMock(CompanionEnrollmentServiceInterface::class);
        $rateLimiter = $this->createMock(EndpointRateLimiterInterface::class);
        $service->method('claim')->willThrowException(new DomainException('Invalid enrollment.'));

        $input = new ClaimCompanionEnrollmentInputDTO();
        $input->enrollmentToken = str_repeat('b', 64);
        $input->platform = 'wearos';
        $input->appVersion = '1.0.0';

        $this->expectException(NotFoundHttpException::class);
        new ClaimCompanionEnrollmentProcessor($service, $rateLimiter)
            ->process($input, new Post());
    }
}
