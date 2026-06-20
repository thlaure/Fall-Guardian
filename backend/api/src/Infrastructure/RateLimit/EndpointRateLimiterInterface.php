<?php

declare(strict_types=1);

namespace App\Infrastructure\RateLimit;

interface EndpointRateLimiterInterface
{
    public function consume(string $bucketName, int $limit, int $windowSeconds, ?string $subject = null): void;
}
