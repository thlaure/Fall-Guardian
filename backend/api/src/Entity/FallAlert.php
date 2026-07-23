<?php

declare(strict_types=1);

namespace App\Entity;

use App\Enum\FallAlertStatus;
use App\Infrastructure\Persistence\DoctrineFallAlertRepository;
use DateTimeImmutable;
use Doctrine\Common\Collections\ArrayCollection;
use Doctrine\Common\Collections\Collection;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineFallAlertRepository::class)]
#[ORM\Table(name: 'fall_alerts')]
#[ORM\UniqueConstraint(name: 'uniq_alerts_device_client', columns: ['device_id', 'client_alert_id'])]
#[ORM\Index(name: 'idx_fall_alerts_dispatch_due', columns: ['status', 'cancel_deadline_at', 'dispatch_claimed_at'])]
class FallAlert
{
    public const int GRACE_PERIOD_SECONDS = 30;

    public const int DELIVERY_RECEIPT_TIMEOUT_SECONDS = 15;

    public const int ACKNOWLEDGEMENT_TIMEOUT_SECONDS = 60;

    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

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
        private ?float $longitude, ?DateTimeImmutable $receivedAt = null)
    {
        $this->id = Uuid::v7();
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

    public function claimForDispatch(DateTimeImmutable $now, DateTimeImmutable $staleBefore): bool
    {
        $isDue = FallAlertStatus::Received === $this->status
            && $now >= $this->cancelDeadlineAt;
        $isStaleClaim = FallAlertStatus::Dispatching === $this->status
            && $this->dispatchClaimedAt instanceof DateTimeImmutable
            && $this->dispatchClaimedAt <= $staleBefore;

        if (!$isDue && !$isStaleClaim) {
            return false;
        }

        $this->status = FallAlertStatus::Dispatching;
        $this->dispatchClaimedAt = $now;
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
