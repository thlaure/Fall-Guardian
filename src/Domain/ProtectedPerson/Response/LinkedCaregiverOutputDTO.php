<?php

declare(strict_types=1);

namespace App\Domain\ProtectedPerson\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\ProtectedPerson\Provider\LinkedCaregiversProvider;
use App\Entity\CaregiverLink;
use DateTimeInterface;

#[ApiResource(operations: [
    new GetCollection(
        uriTemplate: '/api/v1/protected/linked-caregivers',
        output: self::class,
        openapi: new Operation(
            tags: ['Protected person'],
            summary: 'List linked caregivers',
            description: 'Returns active caregiver links for the authenticated protected-person device.',
            security: [['deviceBearer' => []]],
        ),
        provider: LinkedCaregiversProvider::class,
    ),
])]
final readonly class LinkedCaregiverOutputDTO
{
    public function __construct(
        public string $linkedAt,
        public string $platform,
    ) {
    }

    public static function fromLink(CaregiverLink $link): self
    {
        return new self(
            linkedAt: $link->getCreatedAt()->format(DateTimeInterface::ATOM),
            platform: $link->getCaregiverDevice()->getPlatform(),
        );
    }
}
