<?php

declare(strict_types=1);

namespace App\Entity;

use App\Enum\CaregiverLinkStatus;
use App\Infrastructure\Persistence\DoctrineCaregiverLinkRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineCaregiverLinkRepository::class)]
#[ORM\Table(name: 'caregiver_links')]
#[ORM\UniqueConstraint(name: 'uniq_caregiver_links_pair', columns: ['protected_device_id', 'caregiver_device_id'])]
class CaregiverLink
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(length: 32, enumType: CaregiverLinkStatus::class)]
    private CaregiverLinkStatus $status = CaregiverLinkStatus::Active;

    #[ORM\Column(name: 'created_at')]
    private DateTimeImmutable $createdAt;

    #[ORM\Column(name: 'updated_at')]
    private DateTimeImmutable $updatedAt;

    public function __construct(#[ORM\ManyToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(name: 'protected_device_id', nullable: false, onDelete: 'CASCADE')]
        private Device $protectedDevice, #[ORM\ManyToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(name: 'caregiver_device_id', nullable: false, onDelete: 'CASCADE')]
        private Device $caregiverDevice)
    {
        $now = new DateTimeImmutable();
        $this->id = Uuid::v7();
        $this->createdAt = $now;
        $this->updatedAt = $now;
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getProtectedDevice(): Device
    {
        return $this->protectedDevice;
    }

    public function getCaregiverDevice(): Device
    {
        return $this->caregiverDevice;
    }

    public function getStatus(): CaregiverLinkStatus
    {
        return $this->status;
    }

    public function isActive(): bool
    {
        return CaregiverLinkStatus::Active === $this->status;
    }

    public function getCreatedAt(): DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): DateTimeImmutable
    {
        return $this->updatedAt;
    }

    public function revoke(): void
    {
        $this->status = CaregiverLinkStatus::Revoked;
        $this->updatedAt = new DateTimeImmutable();
    }
}
