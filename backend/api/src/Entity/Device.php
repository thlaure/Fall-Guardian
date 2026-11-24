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

    #[ORM\ManyToOne(targetEntity: ProtectedPerson::class, cascade: ['persist'])]
    #[ORM\JoinColumn(name: 'protected_person_id', nullable: true, onDelete: 'CASCADE')]
    private ?ProtectedPerson $protectedPerson = null;

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
        $this->protectedPerson = new ProtectedPerson();
        $this->createdAt = $now;
        $this->updatedAt = $now;
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

    public function rotateTokenHash(string $tokenHash): void
    {
        $this->tokenHash = $tokenHash;
        $this->touch();
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

    public const int LAST_SEEN_RESOLUTION_SECONDS = 300;

    /**
     * Records activity at most once per LAST_SEEN_RESOLUTION_SECONDS so that
     * authenticated requests do not each cause a database write.
     *
     * @return bool true when the timestamp changed and needs persisting
     */
    public function touchSeenAt(?DateTimeImmutable $now = null): bool
    {
        $now ??= new DateTimeImmutable();

        if ($this->lastSeenAt instanceof DateTimeImmutable
            && $now->getTimestamp() - $this->lastSeenAt->getTimestamp() < self::LAST_SEEN_RESOLUTION_SECONDS) {
            return false;
        }

        $this->lastSeenAt = $now;
        $this->touch();

        return true;
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

        if (DeviceType::Caregiver === $deviceType) {
            $this->protectedPerson = null;
        } elseif (!$this->protectedPerson instanceof ProtectedPerson) {
            $this->protectedPerson = new ProtectedPerson();
        }
        $this->touch();
    }

    public function getProtectedPerson(): ?ProtectedPerson
    {
        return $this->protectedPerson;
    }

    public function attachToProtectedPerson(ProtectedPerson $protectedPerson): void
    {
        $this->protectedPerson = $protectedPerson;
        $this->deviceType = DeviceType::ProtectedPerson;
        $this->touch();
    }

    public function isCaregiver(): bool
    {
        return DeviceType::Caregiver === $this->deviceType;
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
