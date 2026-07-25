<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Entity\ProtectedPerson;
use App\Enum\FallDetectionSource;
use App\Enum\FallResolution;
use App\Shared\DateTime\ApiDateTimeFormatter;
use DateTimeImmutable;
use Psr\Clock\ClockInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\DelayStamp;

final readonly class AlertIngestionService implements AlertIngestionServiceInterface
{
    /**
     * How long a submitted alert waits, cancellable, before the caregiver
     * push is actually dispatched. Owning this window server-side means the
     * escalation still fires even if the assisted phone is locked/suspended
     * before any client-side countdown would have completed.
     */
    public const int GRACE_PERIOD_SECONDS = FallAlert::GRACE_PERIOD_SECONDS;

    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private MessageBusInterface $messageBus,
        private ClockInterface $clock,
    ) {
    }

    public function createAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude, int $revision = 1, FallDetectionSource $detectionSource = FallDetectionSource::AssistedPhone, FallResolution $resolution = FallResolution::Unknown): FallAlert
    {
        $fallTimestamp = ApiDateTimeFormatter::normalizeToUtc($fallTimestamp);
        $existing = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if ($existing instanceof FallAlert) {
            if ($existing->applyNewerIncidentMetadata($revision, $detectionSource, $resolution)) {
                $this->fallAlertRepository->save($existing);
            }

            return $existing;
        }

        $now = $this->clock->now();
        $alert = new FallAlert($device, $clientAlertId, $fallTimestamp, $locale, $latitude, $longitude, $now, $revision, $detectionSource, $resolution);
        $this->fallAlertRepository->save($alert);

        $this->messageBus->dispatch(
            new SendFallAlertPushMessage($alert->getId()->toRfc4122()),
            [new DelayStamp($this->remainingGraceMs($alert, $now))],
        );

        return $alert;
    }

    private function remainingGraceMs(FallAlert $alert, DateTimeImmutable $now): int
    {
        $remainingSeconds = (float) $alert->getCancelDeadlineAt()->format('U.u') - (float) $now->format('U.u');

        return max(0, (int) round($remainingSeconds * 1000));
    }

    public function createCancelledAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude, int $revision = 1, FallDetectionSource $detectionSource = FallDetectionSource::AssistedPhone, FallResolution $resolution = FallResolution::Unknown): FallAlert
    {
        $fallTimestamp = ApiDateTimeFormatter::normalizeToUtc($fallTimestamp);
        $existing = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);
        $now = $this->clock->now();

        if ($existing instanceof FallAlert) {
            if ($revision < $existing->getRevision()) {
                return $existing;
            }

            if ($existing->applyNewerIncidentMetadata($revision, $detectionSource, $resolution)) {
                $this->fallAlertRepository->save($existing);
            }

            return $this->fallAlertRepository->cancelPending($device, $clientAlertId, $now) ?? $existing;
        }

        $alert = new FallAlert($device, $clientAlertId, $fallTimestamp, $locale, $latitude, $longitude, $now, $revision, $detectionSource, $resolution);
        $alert->cancel($now);
        $this->fallAlertRepository->save($alert);

        return $alert;
    }

    public function cancelAlert(Device $device, string $clientAlertId): ?FallAlert
    {
        return $this->fallAlertRepository->cancelPending($device, $clientAlertId, $this->clock->now());
    }

    public function getAlertForDevice(Device $device, string $alertId): ?FallAlert
    {
        $alert = $this->fallAlertRepository->findById($alertId);

        if (!$alert instanceof FallAlert || !$this->belongsToSameProtectedPerson($alert, $device)) {
            return null;
        }

        return $alert;
    }

    public function attachLocation(Device $device, string $clientAlertId, ?float $latitude, ?float $longitude): ?FallAlert
    {
        $alert = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if (!$alert instanceof FallAlert) {
            return null;
        }

        $alert->updateLocation($latitude, $longitude);
        $this->fallAlertRepository->save($alert);

        return $alert;
    }

    private function belongsToSameProtectedPerson(FallAlert $alert, Device $device): bool
    {
        $alertPerson = $alert->getProtectedPerson();
        $devicePerson = $device->getProtectedPerson();

        if ($alertPerson instanceof ProtectedPerson && $devicePerson instanceof ProtectedPerson) {
            return $alertPerson->getId()->equals($devicePerson->getId());
        }

        return $alert->getDevice()->getId()->equals($device->getId());
    }
}
