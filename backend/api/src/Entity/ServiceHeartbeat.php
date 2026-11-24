<?php

declare(strict_types=1);

namespace App\Entity;

use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;

/**
 * Last-alive timestamp written by background processes (alert reconciler,
 * messenger worker) so readiness checks can detect a stalled escalation loop.
 */
#[ORM\Entity]
#[ORM\Table(name: 'service_heartbeats')]
class ServiceHeartbeat
{
    public function __construct(
        #[ORM\Id]
        #[ORM\Column(length: 64)]
        private string $name,
        #[ORM\Column(name: 'beat_at')]
        private DateTimeImmutable $beatAt,
    ) {
    }

    public function getName(): string
    {
        return $this->name;
    }

    public function getBeatAt(): DateTimeImmutable
    {
        return $this->beatAt;
    }
}
