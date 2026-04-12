<?php

declare(strict_types=1);

namespace App\Entity;

use App\Infrastructure\Persistence\DoctrineCaregiverInviteRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineCaregiverInviteRepository::class)]
#[ORM\Table(name: 'caregiver_invites')]
#[ORM\UniqueConstraint(name: 'uniq_caregiver_invites_code', columns: ['code'])]
class CaregiverInvite
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'created_at')]
    private DateTimeImmutable $createdAt;

    #[ORM\Column(name: 'used_at', nullable: true)]
    private ?DateTimeImmutable $usedAt = null;

    public function __construct(#[ORM\ManyToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private Device $device, #[ORM\Column(length: 8)]
        private string $code, #[ORM\Column(name: 'expires_at')]
        private DateTimeImmutable $expiresAt)
    {
        $this->id = Uuid::v7();
        $this->createdAt = new DateTimeImmutable();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getDevice(): Device
    {
        return $this->device;
    }

    public function getCode(): string
    {
        return $this->code;
    }

    public function getExpiresAt(): DateTimeImmutable
    {
        return $this->expiresAt;
    }

    public function isExpired(): bool
    {
        return $this->expiresAt <= new DateTimeImmutable();
    }

    public function isUsed(): bool
    {
        return $this->usedAt instanceof DateTimeImmutable;
    }

    public function getCreatedAt(): DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUsedAt(): ?DateTimeImmutable
    {
        return $this->usedAt;
    }

    public function markUsed(): void
    {
        $this->usedAt = new DateTimeImmutable();
    }
}
