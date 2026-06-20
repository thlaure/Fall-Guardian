<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Processor\AcknowledgeAlertProcessor;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{id}/acknowledge',
        input: false,
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Caregiver alerts'],
            summary: 'Acknowledge a fall alert',
            description: 'Records that the authenticated caregiver has seen an alert belonging to a linked protected person.',
            security: [['deviceBearer' => []]],
        ),
        processor: AcknowledgeAlertProcessor::class,
    ),
])]
final class AcknowledgeAlertInputDTO
{
    // alertId comes from the URI variable {id}, body is intentionally empty
}
