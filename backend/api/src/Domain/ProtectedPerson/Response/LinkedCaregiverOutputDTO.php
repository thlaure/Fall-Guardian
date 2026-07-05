<?php

declare(strict_types=1);

namespace App\Domain\ProtectedPerson\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\ProtectedPerson\Processor\RevokeCaregiverLinkProcessor;
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
    new Delete(
        uriTemplate: '/api/v1/protected/linked-caregivers/{id}',
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Protected person'],
            summary: 'Remove a linked caregiver',
            description: 'Revokes an active caregiver link. The caregiver will no longer receive fall alerts from this device.',
            security: [['deviceBearer' => []]],
        ),
        processor: RevokeCaregiverLinkProcessor::class,
    ),
])]
final readonly class LinkedCaregiverOutputDTO
{
    public function __construct(
        public string $id,
        public string $caregiverDeviceId,
        public string $linkedAt,
        public string $platform,
        public ?string $protectedPersonName,
        public ?string $caregiverName,
    ) {
    }

    public static function fromLink(CaregiverLink $link): self
    {
        return new self(
            id: $link->getId()->toRfc4122(),
            caregiverDeviceId: $link->getCaregiverDevice()->getPublicId(),
            linkedAt: $link->getCreatedAt()->format(DateTimeInterface::ATOM),
            platform: $link->getCaregiverDevice()->getPlatform(),
            protectedPersonName: $link->getProtectedPersonName(),
            caregiverName: $link->getCaregiverName(),
        );
    }
}
