<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Provider\CaregiverAlertsProvider;
use App\Entity\FallAlert;
use App\Shared\DateTime\ApiDateTimeFormatter;

#[ApiResource(operations: [
    new GetCollection(
        uriTemplate: '/api/v1/caregiver/alerts',
        output: self::class,
        openapi: new Operation(
            tags: ['Caregiver alerts'],
            summary: 'List caregiver fall alerts',
            description: 'Returns alerts from protected persons linked to the authenticated caregiver device, including acknowledgement state.',
            security: [['deviceBearer' => []]],
        ),
        provider: CaregiverAlertsProvider::class,
    ),
])]
final readonly class CaregiverAlertOutputDTO
{
    public function __construct(
        public string $id,
        public string $status,
        public string $fallDetectedAt,
        public ?float $latitude,
        public ?float $longitude,
        public bool $acknowledged,
        public ?string $cancelledAt,
        public string $protectedDeviceId,
        public string $protectedDevicePlatform,
    ) {
    }

    public static function fromEntity(FallAlert $alert, bool $acknowledged = false): self
    {
        return new self(
            $alert->getId()->toRfc4122(),
            $alert->getStatus()->value,
            ApiDateTimeFormatter::formatUtc($alert->getFallDetectedAt()),
            $alert->getLatitude(),
            $alert->getLongitude(),
            $acknowledged,
            null === $alert->getCancelledAt() ? null : ApiDateTimeFormatter::formatUtc($alert->getCancelledAt()),
            $alert->getDevice()->getPublicId(),
            $alert->getDevice()->getPlatform(),
        );
    }
}
