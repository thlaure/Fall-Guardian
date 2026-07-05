<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use App\Shared\DateTime\ApiDateTimeFormatter;
use DateTimeImmutable;
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
    public const int GRACE_PERIOD_SECONDS = 30;

    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private MessageBusInterface $messageBus,
    ) {
    }

    public function createAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude): FallAlert
    {
        $fallTimestamp = ApiDateTimeFormatter::normalizeToUtc($fallTimestamp);
        $existing = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if ($existing instanceof FallAlert) {
            return $existing;
        }

        $alert = new FallAlert($device, $clientAlertId, $fallTimestamp, $locale, $latitude, $longitude);
        $this->fallAlertRepository->save($alert);

        $this->messageBus->dispatch(
            new SendFallAlertPushMessage($alert->getId()->toRfc4122()),
            [new DelayStamp($this->remainingGraceMs($fallTimestamp))],
        );

        return $alert;
    }

    private function remainingGraceMs(DateTimeImmutable $fallTimestamp): int
    {
        $graceExpiresAt = $fallTimestamp->modify(sprintf('+%d seconds', self::GRACE_PERIOD_SECONDS));
        $remainingSeconds = (float) $graceExpiresAt->format('U.u') - (float) new DateTimeImmutable()->format('U.u');

        return max(0, (int) round($remainingSeconds * 1000));
    }

    public function createCancelledAlert(Device $device, string $clientAlertId, DateTimeImmutable $fallTimestamp, string $locale, ?float $latitude, ?float $longitude): FallAlert
    {
        $fallTimestamp = ApiDateTimeFormatter::normalizeToUtc($fallTimestamp);
        $existing = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);

        if ($existing instanceof FallAlert) {
            if (FallAlertStatus::Cancelled !== $existing->getStatus()) {
                $existing->cancel();
                $this->fallAlertRepository->save($existing);
            }

            return $existing;
        }

        $alert = new FallAlert($device, $clientAlertId, $fallTimestamp, $locale, $latitude, $longitude);
        $alert->cancel();
        $this->fallAlertRepository->save($alert);

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
}
