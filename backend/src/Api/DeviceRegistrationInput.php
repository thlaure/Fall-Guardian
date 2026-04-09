<?php

declare(strict_types=1);

namespace App\Api;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\Dto\DeviceRegistrationOutput;
use App\State\DeviceRegistrationProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/devices/register',
        output: DeviceRegistrationOutput::class,
        processor: DeviceRegistrationProcessor::class,
        read: false,
    ),
])]
final class DeviceRegistrationInput
{
    #[Assert\NotBlank]
    #[Assert\Choice(choices: ['ios', 'android'])]
    public string $platform = '';

    #[Assert\NotBlank]
    #[Assert\Length(max: 32)]
    public string $appVersion = '';
}
