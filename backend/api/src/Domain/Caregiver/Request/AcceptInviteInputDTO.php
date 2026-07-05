<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Processor\AcceptInviteProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/invites/{code}/accept',
        input: self::class,
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Caregiver links'],
            summary: 'Accept a caregiver invitation',
            description: 'Links the authenticated caregiver device to the protected person associated with this valid invitation code.',
            security: [['deviceBearer' => []]],
        ),
        processor: AcceptInviteProcessor::class,
    ),
])]
final class AcceptInviteInputDTO
{
    #[Assert\NotBlank(allowNull: true)]
    #[Assert\Length(min: 2, max: 120)]
    public ?string $protectedPersonName = null;

    #[Assert\NotBlank(allowNull: true)]
    #[Assert\Length(min: 2, max: 120)]
    public ?string $caregiverName = null;
}
