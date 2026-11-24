<?php

declare(strict_types=1);

namespace App\Domain\Healthcheck\Port;

use DateTimeImmutable;

interface HeartbeatRepositoryInterface
{
    public const string RECONCILER = 'alert_reconciler';

    /**
     * Prefix of messenger worker heartbeats. Each worker beats under its own
     * name (see messengerWorkerName()) so one live worker cannot hide a dead one.
     */
    public const string MESSENGER = 'messenger';

    public function beat(string $name, DateTimeImmutable $at): void;

    public function lastBeatAt(string $name): ?DateTimeImmutable;

    /** Most recent heartbeat among all names starting with `$prefix:`. */
    public function lastBeatAtAmong(string $prefix): ?DateTimeImmutable;
}
