<?php

declare(strict_types=1);

namespace App\Domain\Alert\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Alert\Processor\CancelFallAlertProcessor;
use App\Domain\Alert\Response\FallAlertOutputDTO;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{clientAlertId}/cancel',
        input: false,
        output: FallAlertOutputDTO::class,
        read: false,
        deserialize: false,
        openapi: new Operation(
            tags: ['Fall alerts'],
            summary: 'Cancel a fall alert',
            description: 'Cancels a previously reported fall by its clientAlertId. Only the protected-person device that reported the alert may cancel it.',
            security: [['deviceBearer' => []]],
        ),
        processor: CancelFallAlertProcessor::class,
    ),
])]
final class CancelFallAlertInputDTO
{
}
