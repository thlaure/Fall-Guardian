<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceApiUser;
use App\Infrastructure\Http\Security\DeviceTokenAuthenticator;
use App\Infrastructure\Http\Security\DeviceTokenHasher;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Exception\AuthenticationException;
use Symfony\Component\Security\Http\Authenticator\Passport\Badge\UserBadge;

final class DeviceTokenAuthenticatorTest extends TestCase
{
    private DeviceRepositoryInterface&MockObject $deviceRepository;

    private DeviceTokenAuthenticator $authenticator;

    protected function setUp(): void
    {
        $this->deviceRepository = $this->createMock(DeviceRepositoryInterface::class);
        $this->authenticator = new DeviceTokenAuthenticator($this->deviceRepository, new DeviceTokenHasher('test-secret'));
    }

    #[Test]
    public function itSupportsApiRoutesExceptDeviceRegistration(): void
    {
        self::assertTrue($this->authenticator->supports(Request::create('/api/v1/alerts')));
        self::assertFalse($this->authenticator->supports(Request::create('/api/v1/devices/register')));
        self::assertFalse($this->authenticator->supports(Request::create('/health')));
    }

    #[Test]
    public function itRejectsRequestsWithoutBearerToken(): void
    {
        $this->expectException(AuthenticationException::class);
        $this->expectExceptionMessage('Missing bearer token.');

        $this->authenticator->authenticate(Request::create('/api/v1/alerts'));
    }

    #[Test]
    public function itLoadsDeviceUserFromBearerToken(): void
    {
        $plainToken = 'plain-token';
        $hashedToken = hash_hmac('sha256', $plainToken, 'test-secret');
        $device = new Device('device-id', $hashedToken, 'ios', '1.0.0');

        $this->deviceRepository
            ->expects($this->once())
            ->method('findActiveByTokenHash')
            ->with($hashedToken)
            ->willReturn($device);
        $this->deviceRepository->expects($this->once())->method('save')->with($device);

        $request = Request::create('/api/v1/alerts');
        $request->headers->set('Authorization', 'Bearer '.$plainToken);

        $passport = $this->authenticator->authenticate($request);
        $userBadge = $passport->getBadge(UserBadge::class);
        self::assertInstanceOf(UserBadge::class, $userBadge);
        $user = $userBadge->getUser();

        self::assertInstanceOf(DeviceApiUser::class, $user);
        self::assertSame('device:device-id', $user->getUserIdentifier());
        self::assertNotNull($device->getLastSeenAt());
    }

    #[Test]
    public function itAcceptsLegacySha256TokenHashDuringTransition(): void
    {
        $plainToken = 'plain-token';
        $hmacHash = hash_hmac('sha256', $plainToken, 'test-secret');
        $legacyHash = hash('sha256', $plainToken);
        $device = new Device('device-id', $legacyHash, 'ios', '1.0.0');

        $this->deviceRepository
            ->expects($this->exactly(2))
            ->method('findActiveByTokenHash')
            ->willReturnMap([
                [$hmacHash, null],
                [$legacyHash, $device],
            ]);
        $this->deviceRepository->expects($this->once())->method('save')->with($device);

        $request = Request::create('/api/v1/alerts');
        $request->headers->set('Authorization', 'Bearer '.$plainToken);

        $passport = $this->authenticator->authenticate($request);
        $userBadge = $passport->getBadge(UserBadge::class);
        self::assertInstanceOf(UserBadge::class, $userBadge);

        self::assertInstanceOf(DeviceApiUser::class, $userBadge->getUser());
        self::assertNotNull($device->getLastSeenAt());
        self::assertSame($hmacHash, $device->getTokenHash());
    }

    #[Test]
    public function itRejectsUnknownDeviceToken(): void
    {
        $this->deviceRepository->method('findActiveByTokenHash')->willReturn(null);

        $request = Request::create('/api/v1/alerts');
        $request->headers->set('Authorization', 'Bearer unknown');

        $passport = $this->authenticator->authenticate($request);
        $userBadge = $passport->getBadge(UserBadge::class);
        self::assertInstanceOf(UserBadge::class, $userBadge);

        $this->expectException(AuthenticationException::class);
        $this->expectExceptionMessage('Invalid device token.');

        $userBadge->getUser();
    }

    #[Test]
    public function itReturnsJsonAuthenticationFailureResponse(): void
    {
        $response = $this->authenticator->onAuthenticationFailure(
            Request::create('/api/v1/alerts'),
            new AuthenticationException('Invalid device token.'),
        );

        self::assertSame(Response::HTTP_UNAUTHORIZED, $response->getStatusCode());
        self::assertSame(
            '{"error":"unauthorized","message":"An authentication exception occurred."}',
            $response->getContent(),
        );
    }

    #[Test]
    public function itReturnsNullOnAuthenticationSuccess(): void
    {
        self::assertNull($this->authenticator->onAuthenticationSuccess(
            Request::create('/api/v1/alerts'),
            $this->createMock(TokenInterface::class),
            'main',
        ));
    }
}
