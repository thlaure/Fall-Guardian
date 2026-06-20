<?php

declare(strict_types=1);

namespace App\Infrastructure\RateLimit;

final readonly class NullEndpointRateLimiter implements EndpointRateLimiterInterface
{
    public function consume(string $bucketName, int $limit, int $windowSeconds, ?string $subject = null): void
    {
    }
}
