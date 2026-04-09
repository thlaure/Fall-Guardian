<?php

declare(strict_types=1);

namespace App\Application;

use App\Entity\Device;
use App\Entity\FallAlert;
use App\Message\SendFallAlertMessage;
use App\Repository\FallAlertRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Uid\Uuid;

final class AlertIngestionService
{
    public function __construct(
        private readonly FallAlertRepository $fallAlertRepository,
        private readonly EntityManagerInterface $entityManager,
        private readonly MessageBusInterface $messageBus,
    ) {
    }

    public function createAlert(Device $device, string $clientAlertId, \DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude): FallAlert
    {
        $existing = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if (null !== $existing) {
            return $existing;
        }

        $alert = new FallAlert($device, $clientAlertId, $fallTimestamp, $locale, $latitude, $longitude);
        $this->entityManager->persist($alert);
        $this->entityManager->flush();

        $this->messageBus->dispatch(new SendFallAlertMessage($alert->getId()->toRfc4122()));

        return $alert;
    }

    public function cancelAlert(Device $device, string $clientAlertId): ?FallAlert
    {
        $alert = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if (null === $alert) {
            return null;
        }

        $alert->cancel();
        $this->entityManager->flush();

        return $alert;
    }

    public function getAlertForDevice(Device $device, string $alertId): ?FallAlert
    {
        $alert = $this->fallAlertRepository->find(Uuid::fromString($alertId));

        if (!$alert instanceof FallAlert || !$alert->getDevice()->getId()->equals($device->getId())) {
            return null;
        }

        return $alert;
    }
}
