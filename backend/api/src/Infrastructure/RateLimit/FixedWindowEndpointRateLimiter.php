<?php

declare(strict_types=1);

namespace App\Infrastructure\RateLimit;

use App\Entity\RateLimitBucket;
use DateTimeImmutable;
use Doctrine\DBAL\LockMode;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;

final readonly class FixedWindowEndpointRateLimiter implements EndpointRateLimiterInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private RequestStack $requestStack,
    ) {
    }

    public function consume(string $bucketName, int $limit, int $windowSeconds, ?string $subject = null): void
    {
        $now = new DateTimeImmutable();
        $subject ??= $this->requestStack->getCurrentRequest()?->getClientIp() ?? 'unknown';
        $bucketId = hash('sha256', $bucketName.'|'.$subject);

        $this->entityManager->wrapInTransaction(function () use ($bucketId, $now, $limit, $windowSeconds): void {
            $bucket = $this->entityManager->find(RateLimitBucket::class, $bucketId, LockMode::PESSIMISTIC_WRITE);

            if (!$bucket instanceof RateLimitBucket) {
                $bucket = new RateLimitBucket($bucketId, $now);
                $this->entityManager->persist($bucket);
            }

            $elapsedSeconds = $now->getTimestamp() - $bucket->getWindowStartAt()->getTimestamp();

            if ($elapsedSeconds >= $windowSeconds) {
                $bucket->reset($now);
                $elapsedSeconds = 0;
            }

            if ($bucket->getHits() >= $limit) {
                $retryAfter = max(1, $windowSeconds - $elapsedSeconds);

                throw new TooManyRequestsHttpException($retryAfter, 'Too many requests. Please retry later.');
            }

            $bucket->hit();
        });
    }
}
