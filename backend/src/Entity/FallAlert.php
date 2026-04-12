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

    /** @var Collection<int, SmsAttempt> */
    #[ORM\OneToMany(targetEntity: SmsAttempt::class, mappedBy: 'fallAlert', cascade: ['persist', 'remove'], orphanRemoval: true)]
    private Collection $smsAttempts;

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
        $this->smsAttempts = new ArrayCollection();
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

    public function markDispatching(): void
    {
        $this->status = FallAlertStatus::Dispatching;
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

    public function cancel(): void
    {
        $this->status = FallAlertStatus::Cancelled;
        $this->cancelledAt = new DateTimeImmutable();
    }

    public function markAcknowledged(): void
    {
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

    public function getCancelledAt(): ?DateTimeImmutable
    {
        return $this->cancelledAt;
    }

    /** @return Collection<int, SmsAttempt> */
    public function getSmsAttempts(): Collection
    {
        return $this->smsAttempts;
    }

    public function addSmsAttempt(SmsAttempt $smsAttempt): void
    {
        if (!$this->smsAttempts->contains($smsAttempt)) {
            $this->smsAttempts->add($smsAttempt);
        }
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
