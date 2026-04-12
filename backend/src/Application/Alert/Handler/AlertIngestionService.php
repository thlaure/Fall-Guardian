<?php

declare(strict_types=1);

namespace App\Application\Alert\Handler;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Message\SendFallAlertMessage;
use App\Message\SendFallAlertPushMessage;
use DateTimeImmutable;
use Symfony\Component\Messenger\MessageBusInterface;

final readonly class AlertIngestionService
{
    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private MessageBusInterface $messageBus,
    ) {
    }

    public function createAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude): FallAlert
    {
        $existing = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if ($existing instanceof FallAlert) {
            return $existing;
        }

        $alert = new FallAlert($device, $clientAlertId, $fallTimestamp, $locale, $latitude, $longitude);
        $this->fallAlertRepository->save($alert);

        $this->messageBus->dispatch(new SendFallAlertMessage($alert->getId()->toRfc4122()));
        $this->messageBus->dispatch(new SendFallAlertPushMessage($alert->getId()->toRfc4122()));

        return $alert;
    }

    public function cancelAlert(Device $device, string $clientAlertId): ?FallAlert
    {
        $alert = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if (!$alert instanceof FallAlert) {
            return null;
        }

        $alert->cancel();
        $this->fallAlertRepository->save($alert);

        return $alert;
    }

    public function getAlertForDevice(Device $device, string $alertId): ?FallAlert
    {
        $alert = $this->fallAlertRepository->findById($alertId);

        if (!$alert instanceof FallAlert || !$alert->getDevice()->getId()->equals($device->getId())) {
            return null;
        }

        return $alert;
    }
}
