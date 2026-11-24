<?php

declare(strict_types=1);

namespace App\Entity;

use App\Enum\FallAlertStatus;
use App\Enum\FallDetectionSource;
use App\Enum\FallResolution;
use App\Infrastructure\Persistence\DoctrineFallAlertRepository;
use DateTimeImmutable;
use Doctrine\Common\Collections\ArrayCollection;
use Doctrine\Common\Collections\Collection;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineFallAlertRepository::class)]
#[ORM\Table(name: 'fall_alerts')]
#[ORM\UniqueConstraint(name: 'uniq_alerts_device_client', columns: ['device_id', 'client_alert_id'])]
#[ORM\UniqueConstraint(name: 'uniq_alerts_person_client', columns: ['protected_person_id', 'client_alert_id'])]
#[ORM\Index(name: 'idx_fall_alerts_dispatch_due', columns: ['status', 'cancel_deadline_at', 'dispatch_claimed_at'])]
#[ORM\Index(name: 'idx_fall_alerts_retry_due', columns: ['status', 'next_dispatch_retry_at'])]
#[ORM\Index(name: 'idx_fall_alerts_ack_due', columns: ['status', 'acknowledgement_deadline_at'])]
class FallAlert
{
    public const int GRACE_PERIOD_SECONDS = 30;

    public const int DELIVERY_RECEIPT_TIMEOUT_SECONDS = 15;

    public const int ACKNOWLEDGEMENT_TIMEOUT_SECONDS = 60;

    /** Initial dispatch + retries. After this many rounds the outcome is final. */
    public const int MAX_DISPATCH_ATTEMPTS = 6;

    /** Backoff before retry N (1-based), capped by the last value. */
    public const array DISPATCH_RETRY_BACKOFF_SECONDS = [15, 30, 60, 120, 240];

    /** Re-notifications sent to caregivers while an alert stays unacknowledged. */
    public const int MAX_REMINDERS = 3;

    public const int REMINDER_SPACING_SECONDS = 120;

    /**
     * Reminders are only sent while the acknowledgement deadline is recent.
     * This also guarantees that alerts delivered long ago (e.g. before
     * reminders existed) are never re-notified.
     */
    public const int REMINDER_WINDOW_SECONDS = 1800;

    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\ManyToOne(targetEntity: ProtectedPerson::class)]
    #[ORM\JoinColumn(name: 'protected_person_id', nullable: true, onDelete: 'CASCADE')]
    private ?ProtectedPerson $protectedPerson;

    #[ORM\Column(name: 'received_at')]
    private DateTimeImmutable $receivedAt;

    #[ORM\Column(name: 'cancel_deadline_at')]
    private DateTimeImmutable $cancelDeadlineAt;

    #[ORM\Column(name: 'dispatch_claimed_at', nullable: true)]
    private ?DateTimeImmutable $dispatchClaimedAt = null;

    #[ORM\Column(name: 'delivery_receipt_deadline_at', nullable: true)]
    private ?DateTimeImmutable $deliveryReceiptDeadlineAt = null;

    #[ORM\Column(name: 'first_delivery_receipt_at', nullable: true)]
    private ?DateTimeImmutable $firstDeliveryReceiptAt = null;

    #[ORM\Column(name: 'acknowledgement_deadline_at', nullable: true)]
    private ?DateTimeImmutable $acknowledgementDeadlineAt = null;

    #[ORM\Column(length: 32, enumType: FallAlertStatus::class)]
    private FallAlertStatus $status = FallAlertStatus::Received;

    #[ORM\Column(name: 'cancelled_at', nullable: true)]
    private ?DateTimeImmutable $cancelledAt = null;

    #[ORM\Column(name: 'dispatch_attempts', options: ['default' => 0])]
    private int $dispatchAttempts = 0;

    #[ORM\Column(name: 'next_dispatch_retry_at', nullable: true)]
    private ?DateTimeImmutable $nextDispatchRetryAt = null;

    #[ORM\Column(name: 'reminder_count', options: ['default' => 0])]
    private int $reminderCount = 0;

    #[ORM\Column(name: 'last_reminder_at', nullable: true)]
    private ?DateTimeImmutable $lastReminderAt = null;

    /** @var Collection<int, PushAttempt> */
    #[ORM\OneToMany(targetEntity: PushAttempt::class, mappedBy: 'fallAlert', cascade: ['persist', 'remove'], orphanRemoval: true)]
    private Collection $pushAttempts;

    public function __construct(#[ORM\ManyToOne(targetEntity: Device::class, inversedBy: 'alerts')]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private Device $device, #[ORM\Column(name: 'client_alert_id', length: 100)]
        private string $clientAlertId, #[ORM\Column(name: 'fall_detected_at')]
        private DateTimeImmutable $fallDetectedAt, #[ORM\Column(length: 8)]
        private string $locale, #[ORM\Column(nullable: true)]
        private ?float $latitude, #[ORM\Column(nullable: true)]
        private ?float $longitude, ?DateTimeImmutable $receivedAt = null, #[ORM\Column(options: ['default' => 1])]
        private int $revision = 1, #[ORM\Column(name: 'detection_source', length: 32, enumType: FallDetectionSource::class, options: ['default' => 'assisted_phone'])]
        private FallDetectionSource $detectionSource = FallDetectionSource::AssistedPhone, #[ORM\Column(length: 32, enumType: FallResolution::class, options: ['default' => 'unknown'])]
        private FallResolution $resolution = FallResolution::Unknown)
    {
        $this->id = Uuid::v7();
        $this->protectedPerson = $device->getProtectedPerson();
        $this->receivedAt = $receivedAt ?? new DateTimeImmutable();
        $this->cancelDeadlineAt = $this->receivedAt->modify(sprintf('+%d seconds', self::GRACE_PERIOD_SECONDS));
        $this->pushAttempts = new ArrayCollection();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getDevice(): Device
    {
        return $this->device;
    }

    public function getProtectedPerson(): ?ProtectedPerson
    {
        return $this->protectedPerson;
    }

    public function getClientAlertId(): string
    {
        return $this->clientAlertId;
    }

    public function getFallDetectedAt(): DateTimeImmutable
    {
        return $this->fallDetectedAt;
    }

    public function getReceivedAt(): DateTimeImmutable
    {
        return $this->receivedAt;
    }

    public function getCancelDeadlineAt(): DateTimeImmutable
    {
        return $this->cancelDeadlineAt;
    }

    public function getDispatchClaimedAt(): ?DateTimeImmutable
    {
        return $this->dispatchClaimedAt;
    }

    public function getDeliveryReceiptDeadlineAt(): ?DateTimeImmutable
    {
        return $this->deliveryReceiptDeadlineAt;
    }

    public function getFirstDeliveryReceiptAt(): ?DateTimeImmutable
    {
        return $this->firstDeliveryReceiptAt;
    }

    public function getAcknowledgementDeadlineAt(): ?DateTimeImmutable
    {
        return $this->acknowledgementDeadlineAt;
    }

    public function getStatus(): FallAlertStatus
    {
        return $this->status;
    }

    public function getDispatchAttempts(): int
    {
        return $this->dispatchAttempts;
    }

    public function getNextDispatchRetryAt(): ?DateTimeImmutable
    {
        return $this->nextDispatchRetryAt;
    }

    public function getReminderCount(): int
    {
        return $this->reminderCount;
    }

    public function getLastReminderAt(): ?DateTimeImmutable
    {
        return $this->lastReminderAt;
    }

    public function hasDispatchAttemptsLeft(): bool
    {
        return $this->dispatchAttempts < self::MAX_DISPATCH_ATTEMPTS;
    }

    /** Delay before the next dispatch round, based on how many rounds already ran. */
    public static function retryBackoffSeconds(int $completedAttempts): int
    {
        $index = max(0, $completedAttempts - 1);
        $backoff = self::DISPATCH_RETRY_BACKOFF_SECONDS;

        return $backoff[min($index, count($backoff) - 1)];
    }

    public function claimForDispatch(DateTimeImmutable $now, DateTimeImmutable $staleBefore): bool
    {
        $isDue = FallAlertStatus::Received === $this->status
            && $now >= $this->cancelDeadlineAt;
        $isStaleClaim = FallAlertStatus::Dispatching === $this->status
            && $this->dispatchClaimedAt instanceof DateTimeImmutable
            && $this->dispatchClaimedAt <= $staleBefore;
        $isRetryDue = in_array($this->status, [FallAlertStatus::Failed, FallAlertStatus::PartiallySent], true)
            && $this->nextDispatchRetryAt instanceof DateTimeImmutable
            && $this->nextDispatchRetryAt <= $now
            && $this->hasDispatchAttemptsLeft();

        if (!$isDue && !$isStaleClaim && !$isRetryDue) {
            return false;
        }

        $this->status = FallAlertStatus::Dispatching;
        $this->dispatchClaimedAt = $now;
        $this->nextDispatchRetryAt = null;
        ++$this->dispatchAttempts;
        $this->deliveryReceiptDeadlineAt = $now->modify(sprintf('+%d seconds', self::DELIVERY_RECEIPT_TIMEOUT_SECONDS));
        $this->acknowledgementDeadlineAt = $now->modify(sprintf('+%d seconds', self::ACKNOWLEDGEMENT_TIMEOUT_SECONDS));

        return true;
    }

    public function markSent(): void
    {
        $this->status = FallAlertStatus::Sent;
    }

    public function markPartiallySent(): void
    {
        $this->status = FallAlertStatus::PartiallySent;
    }

    public function markFailed(): void
    {
        $this->status = FallAlertStatus::Failed;
    }

    /**
     * Cancelling and acknowledging can race (the protected person cancels while
     * a caregiver is acknowledging the same alert). Once either has happened the
     * alert is in a terminal state: a cancel arriving after an acknowledgement
     * must not silently erase it, and vice versa.
     */
    public function cancel(?DateTimeImmutable $now = null): bool
    {
        if (FallAlertStatus::Cancelled === $this->status) {
            return true;
        }

        $now ??= new DateTimeImmutable();

        if (FallAlertStatus::Received !== $this->status || $now >= $this->cancelDeadlineAt) {
            return false;
        }

        $this->status = FallAlertStatus::Cancelled;
        $this->cancelledAt = $now;

        return true;
    }

    public function markAcknowledged(): void
    {
        if (FallAlertStatus::Cancelled === $this->status) {
            return;
        }

        $this->status = FallAlertStatus::Acknowledged;
    }

    public function markDeliveryReceived(DateTimeImmutable $receivedAt): void
    {
        if (null === $this->firstDeliveryReceiptAt) {
            $this->firstDeliveryReceiptAt = $receivedAt;
        }
    }

    public function getLocale(): string
    {
        return $this->locale;
    }

    public function getLatitude(): ?float
    {
        return $this->latitude;
    }

    public function getLongitude(): ?float
    {
        return $this->longitude;
    }

    public function updateLocation(?float $latitude, ?float $longitude): void
    {
        $this->latitude = $latitude;
        $this->longitude = $longitude;
    }

    public function getCancelledAt(): ?DateTimeImmutable
    {
        return $this->cancelledAt;
    }

    public function getRevision(): int
    {
        return $this->revision;
    }

    public function getDetectionSource(): FallDetectionSource
    {
        return $this->detectionSource;
    }

    public function getResolution(): FallResolution
    {
        return $this->resolution;
    }

    public function applyNewerIncidentMetadata(
        int $revision,
        FallDetectionSource $detectionSource,
        FallResolution $resolution,
    ): bool {
        if ($revision <= $this->revision) {
            return false;
        }

        $this->revision = $revision;
        $this->detectionSource = $detectionSource;
        $this->resolution = $resolution;

        return true;
    }

    /** @return Collection<int, PushAttempt> */
    public function getPushAttempts(): Collection
    {
        return $this->pushAttempts;
    }

    public function addPushAttempt(PushAttempt $pushAttempt): void
    {
        if (!$this->pushAttempts->contains($pushAttempt)) {
            $this->pushAttempts->add($pushAttempt);
        }
    }
}
