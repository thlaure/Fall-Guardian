<?php

declare(strict_types=1);

namespace App\Infrastructure\Time;

use DateTimeImmutable;
use DateTimeZone;
use Doctrine\DBAL\Connection;
use Psr\Clock\ClockInterface;
use RuntimeException;

final readonly class DatabaseClock implements ClockInterface
{
    public function __construct(private Connection $connection)
    {
    }

    public function now(): DateTimeImmutable
    {
        $value = $this->connection->fetchOne("SELECT CURRENT_TIMESTAMP AT TIME ZONE 'UTC'");

        if (!is_string($value)) {
            throw new RuntimeException('Database did not return its current time.');
        }

        return new DateTimeImmutable($value, new DateTimeZone('UTC'));
    }
}
