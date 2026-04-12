<?php

declare(strict_types=1);

namespace App\Entity;

use App\Infrastructure\Persistence\DoctrineCaregiverPushTokenRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineCaregiverPushTokenRepository::class)]
#[ORM\Table(name: 'caregiver_push_tokens')]
#[ORM\UniqueConstraint(name: 'uniq_push_tokens_device', columns: ['device_id'])]
class CaregiverPushToken
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'updated_at')]
    private DateTimeImmutable $updatedAt;

    public function __construct(#[ORM\OneToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private Device $device, #[ORM\Column(name: 'fcm_token', type: \Doctrine\DBAL\Types\Types::TEXT)]
        private string $fcmToken)
    {
        $this->id = Uuid::v7();
        $this->updatedAt = new DateTimeImmutable();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getDevice(): Device
    {
        return $this->device;
    }

    public function getFcmToken(): string
    {
        return $this->fcmToken;
    }

    public function getUpdatedAt(): DateTimeImmutable
    {
        return $this->updatedAt;
    }

    public function update(string $fcmToken): void
    {
        $this->fcmToken = $fcmToken;
        $this->updatedAt = new DateTimeImmutable();
    }
}
