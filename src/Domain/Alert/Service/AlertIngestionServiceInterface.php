<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

use App\Entity\Device;
use App\Entity\FallAlert;
use DateTimeImmutable;

interface AlertIngestionServiceInterface
{
    public function createAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude): FallAlert;

    public function createCancelledAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude): FallAlert;

    public function cancelAlert(Device $device, string $clientAlertId): ?FallAlert;

    public function getAlertForDevice(Device $device, string $alertId): ?FallAlert;
}
