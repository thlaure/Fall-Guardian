<?php

declare(strict_types=1);

namespace App\Entity;

use App\Enum\DeviceType;
use App\Infrastructure\Persistence\DoctrineDeviceRepository;
use DateTimeImmutable;
use Doctrine\Common\Collections\ArrayCollection;
use Doctrine\Common\Collections\Collection;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineDeviceRepository::class)]
#[ORM\Table(name: 'devices')]
#[ORM\UniqueConstraint(name: 'uniq_devices_public_id', columns: ['public_id'])]
#[ORM\UniqueConstraint(name: 'uniq_devices_token_hash', columns: ['token_hash'])]
class Device
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column]
    private bool $revoked = false;

    #[ORM\Column(name: 'created_at')]
    private DateTimeImmutable $createdAt;

    #[ORM\Column(name: 'updated_at')]
    private DateTimeImmutable $updatedAt;

    #[ORM\Column(name: 'last_seen_at', nullable: true)]
    private ?DateTimeImmutable $lastSeenAt = null;

    #[ORM\Column(name: 'device_type', length: 32, enumType: DeviceType::class)]
    private DeviceType $deviceType = DeviceType::ProtectedPerson;

    /** @var Collection<int, EmergencyContact> */
    #[ORM\OneToMany(targetEntity: EmergencyContact::class, mappedBy: 'device', cascade: ['persist', 'remove'], orphanRemoval: true)]
    private Collection $contacts;

    /** @var Collection<int, FallAlert> */
    #[ORM\OneToMany(targetEntity: FallAlert::class, mappedBy: 'device', cascade: ['persist', 'remove'], orphanRemoval: true)]
    private Collection $alerts;

    public function __construct(#[ORM\Column(name: 'public_id', length: 36)]
        private string $publicId, #[ORM\Column(name: 'token_hash', length: 64)]
        private string $tokenHash, #[ORM\Column(length: 16)]
        private string $platform, #[ORM\Column(name: 'app_version', length: 32)]
        private string $appVersion)
    {
        $now = new DateTimeImmutable();
        $this->id = Uuid::v7();
        $this->createdAt = $now;
        $this->updatedAt = $now;
        $this->contacts = new ArrayCollection();
        $this->alerts = new ArrayCollection();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getPublicId(): string
    {
        return $this->publicId;
    }

    public function getTokenHash(): string
    {
        return $this->tokenHash;
    }

    public function getPlatform(): string
    {
        return $this->platform;
    }

    public function getAppVersion(): string
    {
        return $this->appVersion;
    }

    public function isRevoked(): bool
    {
        return $this->revoked;
    }

    public function revoke(): void
    {
        $this->revoked = true;
        $this->touch();
    }

    public function touchSeenAt(): void
    {
        $this->lastSeenAt = new DateTimeImmutable();
        $this->touch();
    }

    public function getCreatedAt(): DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): DateTimeImmutable
    {
        return $this->updatedAt;
    }

    public function getLastSeenAt(): ?DateTimeImmutable
    {
        return $this->lastSeenAt;
    }

    public function getDeviceType(): DeviceType
    {
        return $this->deviceType;
    }

    public function setDeviceType(DeviceType $deviceType): void
    {
        $this->deviceType = $deviceType;
        $this->touch();
    }

    public function isCaregiver(): bool
    {
        return DeviceType::Caregiver === $this->deviceType;
    }

    public function addContact(EmergencyContact $contact): void
    {
        if (!$this->contacts->contains($contact)) {
            $this->contacts->add($contact);
        }
    }

    /** @return Collection<int, EmergencyContact> */
    public function getContacts(): Collection
    {
        return $this->contacts;
    }

    public function addAlert(FallAlert $alert): void
    {
        if (!$this->alerts->contains($alert)) {
            $this->alerts->add($alert);
        }
    }

    private function touch(): void
    {
        $this->updatedAt = new DateTimeImmutable();
    }
}
