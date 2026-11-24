<?php

declare(strict_types=1);

namespace App\Domain\Healthcheck\Port;

use DateTimeImmutable;

interface HeartbeatRepositoryInterface
{
    public const string RECONCILER = 'alert_reconciler';

    public const string MESSENGER = 'messenger';

    public function beat(string $name, DateTimeImmutable $at): void;

    public function lastBeatAt(string $name): ?DateTimeImmutable;
}
