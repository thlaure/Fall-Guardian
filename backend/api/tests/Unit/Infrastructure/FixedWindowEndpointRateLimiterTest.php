<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Entity\RateLimitBucket;
use App\Infrastructure\RateLimit\FixedWindowEndpointRateLimiter;
use DateTimeImmutable;
use Doctrine\DBAL\LockMode;
use Doctrine\ORM\EntityManagerInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;

final class FixedWindowEndpointRateLimiterTest extends TestCase
{
    #[Test]
    public function itCreatesAndConsumesNewBucket(): void
    {
        $entityManager = $this->createMock(EntityManagerInterface::class);
        $entityManager->expects($this->once())->method('persist')->with($this->isInstanceOf(RateLimitBucket::class));
        $entityManager->expects($this->once())
            ->method('find')
            ->with(RateLimitBucket::class, hash('sha256', 'device_registration|203.0.113.10'), LockMode::PESSIMISTIC_WRITE)
            ->willReturn(null);
        $this->executeTransactions($entityManager);

        $limiter = new FixedWindowEndpointRateLimiter($entityManager, $this->requestStack());

        $limiter->consume('device_registration', 20, 60);
    }

    #[Test]
    public function itRejectsWhenBucketLimitIsReached(): void
    {
        $bucket = new RateLimitBucket(
            hash('sha256', 'invite_accept|caregiver-1'),
            new DateTimeImmutable(),
            5,
        );

        $entityManager = $this->createMock(EntityManagerInterface::class);
        $entityManager->method('find')->willReturn($bucket);
        $this->executeTransactions($entityManager);

        $limiter = new FixedWindowEndpointRateLimiter($entityManager, $this->requestStack());

        $this->expectException(TooManyRequestsHttpException::class);

        $limiter->consume('invite_accept', 5, 600, 'caregiver-1');
    }

    #[Test]
    public function itResetsExpiredWindowBeforeConsuming(): void
    {
        $bucket = new RateLimitBucket(
            hash('sha256', 'invite_accept|caregiver-1'),
            new DateTimeImmutable('-61 seconds'),
            5,
        );

        $entityManager = $this->createMock(EntityManagerInterface::class);
        $entityManager->method('find')->willReturn($bucket);
        $this->executeTransactions($entityManager);

        $limiter = new FixedWindowEndpointRateLimiter($entityManager, $this->requestStack());

        $limiter->consume('invite_accept', 5, 60, 'caregiver-1');

        self::assertSame(1, $bucket->getHits());
    }

    private function executeTransactions(EntityManagerInterface&MockObject $entityManager): void
    {
        $entityManager
            ->method('wrapInTransaction')
            ->willReturnCallback(static fn (callable $callback): mixed => $callback());
    }

    private function requestStack(): RequestStack
    {
        $request = Request::create('/');
        $request->server->set('REMOTE_ADDR', '203.0.113.10');

        $requestStack = new RequestStack();
        $requestStack->push($request);

        return $requestStack;
    }
}
