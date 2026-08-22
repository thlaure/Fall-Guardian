<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Processor\RevokeProtectedPersonLinkProcessor;
use App\Domain\Caregiver\Provider\LinkedProtectedPersonsProvider;
use App\Entity\CaregiverLink;
use DateTimeInterface;

#[ApiResource(operations: [
    new GetCollection(
        uriTemplate: '/api/v1/caregiver/protected-persons',
        output: self::class,
        openapi: new Operation(
            tags: ['Caregiver links'],
            summary: 'List linked protected persons',
            description: 'Returns active protected-person links for the authenticated caregiver device.',
            security: [['deviceBearer' => []]],
        ),
        provider: LinkedProtectedPersonsProvider::class,
    ),
    new Delete(
        uriTemplate: '/api/v1/caregiver/protected-persons/{id}',
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Caregiver links'],
            summary: 'Remove a protected-person link',
            description: 'Revokes one link owned by the authenticated caregiver. The protected person and their other caregiver links are unchanged.',
            security: [['deviceBearer' => []]],
        ),
        processor: RevokeProtectedPersonLinkProcessor::class,
    ),
])]
final readonly class LinkedProtectedPersonOutputDTO
{
    public function __construct(
        public string $linkId,
        public string $protectedDeviceId,
        public string $protectedDevicePlatform,
        public string $linkedAt,
        public ?string $protectedPersonName,
    ) {
    }

    public static function fromLink(CaregiverLink $link): self
    {
        $protectedDevice = $link->getProtectedDevice();

        return new self(
            linkId: $link->getId()->toRfc4122(),
            protectedDeviceId: $protectedDevice->getPublicId(),
            protectedDevicePlatform: $protectedDevice->getPlatform(),
            linkedAt: $link->getCreatedAt()->format(DateTimeInterface::ATOM),
            protectedPersonName: $link->getProtectedPersonName(),
        );
    }
}
