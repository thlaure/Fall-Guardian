<?php

declare(strict_types=1);

namespace App\Domain\Device\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Device\Processor\RevokeDeviceProcessor;
use Symfony\Component\HttpFoundation\Response;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/devices/{deviceId}/revoke',
        status: Response::HTTP_NO_CONTENT,
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Devices'],
            summary: 'Revoke a device',
            description: 'Revokes the authenticated device or another protected-person device belonging to the same protected person.',
        ),
        processor: RevokeDeviceProcessor::class,
    ),
])]
final class RevokeDeviceInputDTO
{
}
