<?php

declare(strict_types=1);

namespace App\Domain\Healthcheck\Service;

use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;

/**
 * Heartbeat name of the messenger worker running on this host. In containers
 * the hostname is the container id, so each worker container beats under its
 * own name and its healthcheck (run inside the same container) reads it back.
 */
final class WorkerHeartbeatName
{
    public static function forThisHost(): string
    {
        return self::forHost((string) gethostname());
    }

    public static function forHost(string $hostname): string
    {
        return sprintf('%s:%s', HeartbeatRepositoryInterface::MESSENGER, '' === $hostname ? 'unknown' : $hostname);
    }
}
