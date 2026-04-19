<?php

declare(strict_types=1);

namespace App\Application\Caregiver\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\UI\State\AcceptInviteProcessor;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/invites/{code}/accept',
        input: false,
        output: false,
        read: false,
        processor: AcceptInviteProcessor::class,
    ),
])]
final class AcceptInviteInput
{
    // code comes from the URI variable, not the body — body is intentionally empty
}
