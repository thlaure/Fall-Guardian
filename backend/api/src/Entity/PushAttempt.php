<?php

declare(strict_types=1);

namespace App\Entity;

use App\Enum\PushAttemptStatus;
use App\Infrastructure\Persistence\DoctrinePushAttemptRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrinePushAttemptRepository::class)]
#[ORM\Table(name: 'push_attempts')]
class PushAttempt
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'provider_message_id', nullable: true)]
    private ?string $providerMessageId = null;

    #[ORM\Column(length: 32, enumType: PushAttemptStatus::class)]
    private PushAttemptStatus $status = PushAttemptStatus::Queued;

    #[ORM\Column(name: 'error_code', nullable: true)]
    private ?string $errorCode = null;

    #[ORM\Column(name: 'error_message', type: \Doctrine\DBAL\Types\Types::TEXT, nullable: true)]
    private ?string $errorMessage = null;

    #[ORM\Column(name: 'retry_count')]
    private int $retryCount = 0;

    #[ORM\Column(name: 'queued_at')]
    private DateTimeImmutable $queuedAt;

    #[ORM\Column(name: 'sent_at', nullable: true)]
    private ?DateTimeImmutable $sentAt = null;

    public function __construct(#[ORM\ManyToOne(targetEntity: FallAlert::class, inversedBy: 'pushAttempts')]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private FallAlert $fallAlert, #[ORM\ManyToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private Device $caregiverDevice, #[ORM\Column(length: 32)]
        private string $provider)
    {
        $this->id = Uuid::v7();
        $this->queuedAt = new DateTimeImmutable();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getCaregiverDevice(): Device
    {
        return $this->caregiverDevice;
    }

    public function getStatus(): PushAttemptStatus
    {
        return $this->status;
    }

    public function markSent(?string $providerMessageId): void
    {
        $this->status = PushAttemptStatus::Sent;
        $this->providerMessageId = $providerMessageId;
        $this->sentAt = new DateTimeImmutable();
    }

    public function markFailed(?string $errorCode, string $errorMessage): void
    {
        $this->status = PushAttemptStatus::Failed;
        $this->errorCode = $errorCode;
        $this->errorMessage = $errorMessage;
        ++$this->retryCount;
    }
}
