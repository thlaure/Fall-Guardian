<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\Device;
use App\Entity\FallAlert;
use DateTimeImmutable;

interface FallAlertRepositoryInterface
{
    public function findOneByDeviceAndClientAlertId(Device $device, string $clientAlertId): ?FallAlert;

    public function findById(string $id): ?FallAlert;

    public function claimForDispatch(string $id, DateTimeImmutable $now, DateTimeImmutable $staleBefore): ?FallAlert;

    public function cancelPending(Device $device, string $clientAlertId, DateTimeImmutable $now): ?FallAlert;

    /** @return list<string> */
    public function findDispatchCandidateIds(DateTimeImmutable $now, DateTimeImmutable $staleBefore, int $limit = 100): array;

    /** @return list<FallAlert> */
    public function findByDevice(Device $device, int $limit = 50): array;

    public function save(FallAlert $alert): void;
}
