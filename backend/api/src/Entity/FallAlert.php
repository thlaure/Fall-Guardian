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
class FallAlert
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'received_at')]
    private DateTimeImmutable $receivedAt;

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
        private ?float $longitude)
    {
        $this->id = Uuid::v7();
        $this->receivedAt = new DateTimeImmutable();
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

    public function getStatus(): FallAlertStatus
    {
        return $this->status;
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
    public function cancel(): void
    {
        if (FallAlertStatus::Acknowledged === $this->status) {
            return;
        }

        $this->status = FallAlertStatus::Cancelled;
        $this->cancelledAt = new DateTimeImmutable();
    }

    public function markAcknowledged(): void
    {
        if (FallAlertStatus::Cancelled === $this->status) {
            return;
        }

        $this->status = FallAlertStatus::Acknowledged;
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
