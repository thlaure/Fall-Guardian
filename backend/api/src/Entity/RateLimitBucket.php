<?php

declare(strict_types=1);

namespace App\Entity;

use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'rate_limit_buckets')]
class RateLimitBucket
{
    public function __construct(
        #[ORM\Id]
        #[ORM\Column(length: 64)]
        private string $id,
        #[ORM\Column(name: 'window_start_at')]
        private DateTimeImmutable $windowStartAt,
        #[ORM\Column]
        private int $hits = 0,
    ) {
    }

    public function getWindowStartAt(): DateTimeImmutable
    {
        return $this->windowStartAt;
    }

    public function getHits(): int
    {
        return $this->hits;
    }

    public function reset(DateTimeImmutable $windowStartAt): void
    {
        $this->windowStartAt = $windowStartAt;
        $this->hits = 0;
    }

    public function hit(): void
    {
        ++$this->hits;
    }
}
