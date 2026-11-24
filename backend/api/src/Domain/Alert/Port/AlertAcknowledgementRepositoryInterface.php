<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\AlertAcknowledgement;
use App\Entity\Device;
use App\Entity\FallAlert;
use DateTimeImmutable;

interface AlertAcknowledgementRepositoryInterface
{
    public function findByCaregiverAndAlert(FallAlert $alert, Device $caregiverDevice): ?AlertAcknowledgement;

    public function save(AlertAcknowledgement $ack): void;

    /**
     * Acknowledgement summary per alert (keyed by RFC 4122 alert id). Alerts
     * without any acknowledgement are absent from the result.
     *
     * @param list<FallAlert> $alerts
     *
     * @return array<string, array{count: int, firstAcknowledgedAt: DateTimeImmutable}>
     */
    public function summarizeByAlerts(array $alerts): array;
}
