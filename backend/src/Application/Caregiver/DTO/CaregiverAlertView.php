<?php

declare(strict_types=1);

namespace App\Application\Caregiver\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\GetCollection;
use App\Entity\FallAlert;
use App\UI\State\CaregiverAlertsProvider;
use DateTimeInterface;

#[ApiResource(operations: [
    new GetCollection(
        uriTemplate: '/api/v1/caregiver/alerts',
        output: self::class,
        provider: CaregiverAlertsProvider::class,
    ),
])]
final readonly class CaregiverAlertView
{
    public function __construct(
        public string $id,
        public string $status,
        public string $fallDetectedAt,
        public ?float $latitude,
        public ?float $longitude,
        public bool $acknowledged,
    ) {
    }

    public static function fromEntity(FallAlert $alert, bool $acknowledged = false): self
    {
        return new self(
            $alert->getId()->toRfc4122(),
            $alert->getStatus()->value,
            $alert->getFallDetectedAt()->format(DateTimeInterface::ATOM),
            $alert->getLatitude(),
            $alert->getLongitude(),
            $acknowledged,
        );
    }
}
