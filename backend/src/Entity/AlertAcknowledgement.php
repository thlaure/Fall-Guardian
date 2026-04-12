<?php

declare(strict_types=1);

namespace App\Entity;

use App\Infrastructure\Persistence\DoctrineAlertAcknowledgementRepository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineAlertAcknowledgementRepository::class)]
#[ORM\Table(name: 'alert_acknowledgements')]
#[ORM\UniqueConstraint(name: 'uniq_ack_alert_caregiver', columns: ['fall_alert_id', 'caregiver_device_id'])]
class AlertAcknowledgement
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    private Uuid $id;

    #[ORM\Column(name: 'acknowledged_at')]
    private DateTimeImmutable $acknowledgedAt;

    public function __construct(#[ORM\ManyToOne(targetEntity: FallAlert::class)]
        #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
        private FallAlert $fallAlert, #[ORM\ManyToOne(targetEntity: Device::class)]
        #[ORM\JoinColumn(name: 'caregiver_device_id', nullable: false, onDelete: 'CASCADE')]
        private Device $caregiverDevice)
    {
        $this->id = Uuid::v7();
        $this->acknowledgedAt = new DateTimeImmutable();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getFallAlert(): FallAlert
    {
        return $this->fallAlert;
    }

    public function getCaregiverDevice(): Device
    {
        return $this->caregiverDevice;
    }

    public function getAcknowledgedAt(): DateTimeImmutable
    {
        return $this->acknowledgedAt;
    }
}
