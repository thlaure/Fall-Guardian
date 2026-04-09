<?php

declare(strict_types=1);

namespace App\Entity;

use App\Enum\SmsAttemptStatus;
use App\Repository\SmsAttemptRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: SmsAttemptRepository::class)]
#[ORM\Table(name: 'sms_attempts')]
final class SmsAttempt
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\ManyToOne(targetEntity: FallAlert::class, inversedBy: 'smsAttempts')]
    #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
    private FallAlert $fallAlert;

    #[ORM\ManyToOne(targetEntity: EmergencyContact::class)]
    #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
    private EmergencyContact $contact;

    #[ORM\Column(length: 32)]
    private string $provider;

    #[ORM\Column(name: 'provider_message_id', nullable: true)]
    private ?string $providerMessageId = null;

    #[ORM\Column(enumType: SmsAttemptStatus::class, length: 32)]
    private SmsAttemptStatus $status = SmsAttemptStatus::Queued;

    #[ORM\Column(name: 'error_code', nullable: true)]
    private ?string $errorCode = null;

    #[ORM\Column(name: 'error_message', type: 'text', nullable: true)]
    private ?string $errorMessage = null;

    #[ORM\Column(name: 'retry_count')]
    private int $retryCount = 0;

    #[ORM\Column(name: 'queued_at')]
    private DateTimeImmutable $queuedAt;

    #[ORM\Column(name: 'sent_at', nullable: true)]
    private ?DateTimeImmutable $sentAt = null;

    #[ORM\Column(name: 'delivered_at', nullable: true)]
    private ?DateTimeImmutable $deliveredAt = null;

    public function __construct(FallAlert $fallAlert, EmergencyContact $contact, string $provider)
    {
        $this->id = Uuid::v7();
        $this->fallAlert = $fallAlert;
        $this->contact = $contact;
        $this->provider = $provider;
        $this->queuedAt = new DateTimeImmutable();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getContact(): EmergencyContact
    {
        return $this->contact;
    }

    public function getProviderMessageId(): ?string
    {
        return $this->providerMessageId;
    }

    public function getStatus(): SmsAttemptStatus
    {
        return $this->status;
    }

    public function markSent(?string $providerMessageId): void
    {
        $this->status = SmsAttemptStatus::Sent;
        $this->providerMessageId = $providerMessageId;
        $this->sentAt = new DateTimeImmutable();
    }

    public function markDelivered(): void
    {
        $this->status = SmsAttemptStatus::Delivered;
        $this->deliveredAt = new DateTimeImmutable();
    }

    public function markFailed(?string $errorCode, string $errorMessage): void
    {
        $this->status = SmsAttemptStatus::Failed;
        $this->errorCode = $errorCode;
        $this->errorMessage = $errorMessage;
        ++$this->retryCount;
    }
}
