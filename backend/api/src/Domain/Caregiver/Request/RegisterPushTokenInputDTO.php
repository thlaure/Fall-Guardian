<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Processor\RegisterPushTokenProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/caregiver/push-token',
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Caregiver alerts'],
            summary: 'Register a caregiver notification token',
            description: 'Stores the Firebase Cloud Messaging token used to deliver fall notifications to the authenticated caregiver device.',
            security: [['deviceBearer' => []]],
        ),
        processor: RegisterPushTokenProcessor::class,
    ),
])]
final class RegisterPushTokenInputDTO
{
    #[Assert\NotBlank]
    public string $fcmToken = '';
}
