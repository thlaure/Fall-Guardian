<?php

declare(strict_types=1);

namespace App\Application\Caregiver\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\UI\State\AcknowledgeAlertProcessor;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{id}/acknowledge',
        input: false,
        output: false,
        read: false,
        processor: AcknowledgeAlertProcessor::class,
    ),
])]
final class AcknowledgeAlertInput
{
    // alertId comes from the URI variable {id}, body is intentionally empty
}
