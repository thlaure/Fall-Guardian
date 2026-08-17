<?php

declare(strict_types=1);

namespace App\Domain\ProtectedPerson\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\ProtectedPerson\Processor\RevokeCaregiverLinkProcessor;
use Symfony\Component\HttpFoundation\Response;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/protected/linked-caregivers/{linkId}/revoke',
        status: Response::HTTP_NO_CONTENT,
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Protected person'],
            summary: 'Revoke a linked caregiver',
            description: 'Revokes the caregiver link so it stops receiving fall alerts and location for the authenticated protected-person device.',
            security: [['deviceBearer' => []]],
        ),
        processor: RevokeCaregiverLinkProcessor::class,
    ),
])]
final class RevokeCaregiverLinkInputDTO
{
}
