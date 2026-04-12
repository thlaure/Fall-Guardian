<?php

declare(strict_types=1);

namespace App\Application\Caregiver\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\UI\State\RegisterPushTokenProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/caregiver/push-token',
        output: false,
        read: false,
        processor: RegisterPushTokenProcessor::class,
    ),
])]
final class RegisterPushTokenInput
{
    #[Assert\NotBlank]
    public string $fcmToken = '';
}
