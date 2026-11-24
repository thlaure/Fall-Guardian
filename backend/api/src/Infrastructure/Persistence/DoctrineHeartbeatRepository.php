<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use DateTimeImmutable;
use DateTimeZone;
use Doctrine\DBAL\Connection;
use Doctrine\DBAL\Types\Types;

final readonly class DoctrineHeartbeatRepository implements HeartbeatRepositoryInterface
{
    public function __construct(private Connection $connection)
    {
    }

    public function beat(string $name, DateTimeImmutable $at): void
    {
        $this->connection->executeStatement(
            'INSERT INTO service_heartbeats (name, beat_at) VALUES (:name, :beatAt)'
            .' ON CONFLICT (name) DO UPDATE SET beat_at = EXCLUDED.beat_at',
            ['name' => $name, 'beatAt' => $at],
            ['beatAt' => Types::DATETIME_IMMUTABLE],
        );
    }

    public function lastBeatAt(string $name): ?DateTimeImmutable
    {
        $value = $this->connection->fetchOne('SELECT beat_at FROM service_heartbeats WHERE name = :name', ['name' => $name]);

        return is_string($value) ? new DateTimeImmutable($value, new DateTimeZone('UTC')) : null;
    }

    public function lastBeatAtAmong(string $prefix): ?DateTimeImmutable
    {
        $value = $this->connection->fetchOne(
            'SELECT MAX(beat_at) FROM service_heartbeats WHERE name LIKE :pattern',
            ['pattern' => addcslashes($prefix.':', '%_\\').'%'],
        );

        return is_string($value) ? new DateTimeImmutable($value, new DateTimeZone('UTC')) : null;
    }
}
