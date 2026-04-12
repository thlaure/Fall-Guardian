<?php

declare(strict_types=1);

namespace App\Entity;

use App\Infrastructure\Persistence\DoctrineEmergencyContactRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineEmergencyContactRepository::class)]
#[ORM\Table(name: 'emergency_contacts')]
#[ORM\UniqueConstraint(name: 'uniq_contacts_device_hash', columns: ['device_id', 'phone_hash'])]
class EmergencyContact
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'created_at')]
    private DateTimeImmutable $createdAt;

    #[ORM\Column(name: 'updated_at')]
    private DateTimeImmutable $updatedAt;

    public function __construct(#[ORM\ManyToOne(targetEntity: Device::class, inversedBy: 'contacts')]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private Device $device, #[ORM\Column(length: 100)]
        private string $name, #[ORM\Column(name: 'phone_ciphertext', type: \Doctrine\DBAL\Types\Types::TEXT)]
        private string $phoneCiphertext, #[ORM\Column(name: 'phone_hash', length: 64)]
        private string $phoneHash, #[ORM\Column(name: 'phone_last4', length: 4)]
        private string $phoneLast4, #[ORM\Column]
        private int $position)
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

    public function getDevice(): Device
    {
        return $this->device;
    }

    public function getName(): string
    {
        return $this->name;
    }

    public function getPhoneCiphertext(): string
    {
        return $this->phoneCiphertext;
    }

    public function getPhoneHash(): string
    {
        return $this->phoneHash;
    }

    public function getPhoneLast4(): string
    {
        return $this->phoneLast4;
    }

    public function getPosition(): int
    {
        return $this->position;
    }

    public function getCreatedAt(): DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): DateTimeImmutable
    {
        return $this->updatedAt;
    }
}
