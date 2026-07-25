<?php

declare(strict_types=1);

namespace App\Entity;

use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity]
#[ORM\Table(name: 'companion_enrollments')]
#[ORM\UniqueConstraint(name: 'uniq_companion_enrollment_token', columns: ['token_hash'])]
class CompanionEnrollment
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'created_at')]
    private DateTimeImmutable $createdAt;

    #[ORM\Column(name: 'claimed_at', nullable: true)]
    private ?DateTimeImmutable $claimedAt = null;

    public function __construct(
        #[ORM\ManyToOne(targetEntity: ProtectedPerson::class)]
        #[ORM\JoinColumn(name: 'protected_person_id', nullable: false, onDelete: 'CASCADE')]
        private ProtectedPerson $protectedPerson,
        #[ORM\ManyToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(name: 'created_by_device_id', nullable: false, onDelete: 'CASCADE')]
        private Device $createdByDevice,
        #[ORM\Column(name: 'token_hash', length: 64)]
        private string $tokenHash,
        #[ORM\Column(length: 16)]
        private string $platform,
        #[ORM\Column(name: 'expires_at')]
        private DateTimeImmutable $expiresAt,
    ) {
        $this->id = Uuid::v7();
        $this->createdAt = new DateTimeImmutable();
    }

    public function getProtectedPerson(): ProtectedPerson
    {
        return $this->protectedPerson;
    }

    public function getTokenHash(): string
    {
        return $this->tokenHash;
    }

    public function getPlatform(): string
    {
        return $this->platform;
    }

    public function getExpiresAt(): DateTimeImmutable
    {
        return $this->expiresAt;
    }

    public function claim(DateTimeImmutable $now): bool
    {
        if ($this->claimedAt instanceof DateTimeImmutable || $now >= $this->expiresAt) {
            return false;
        }

        $this->claimedAt = $now;

        return true;
    }
}
