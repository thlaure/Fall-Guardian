<?php

declare(strict_types=1);

namespace App\Domain\Alert\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Alert\Provider\FallAlertProvider;
use App\Entity\FallAlert;

use const DATE_ATOM;

#[ApiResource(operations: [
    new Get(
        uriTemplate: '/api/v1/fall-alerts/{id}',
        openapi: new Operation(
            tags: ['Fall alerts'],
            summary: 'Get a fall alert status',
            description: 'Returns the current lifecycle status of an alert reported by the authenticated protected-person device.',
            security: [['deviceBearer' => []]],
        ),
        provider: FallAlertProvider::class,
    ),
])]
final class FallAlertOutputDTO
{
    public function __construct(
        public string $id,
        public string $clientAlertId,
        public string $status,
        public string $fallTimestamp,
        public ?string $cancelledAt,
    ) {
    }

    public static function fromEntity(FallAlert $alert): self
    {
        return new self(
            $alert->getId()->toRfc4122(),
            $alert->getClientAlertId(),
            $alert->getStatus()->value,
            $alert->getFallDetectedAt()->format(DATE_ATOM),
            $alert->getCancelledAt()?->format(DATE_ATOM),
        );
    }
}
