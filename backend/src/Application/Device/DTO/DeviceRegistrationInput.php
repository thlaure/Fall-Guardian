<?php

declare(strict_types=1);

namespace App\Application\Device\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\UI\State\DeviceRegistrationProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/devices/register',
        output: DeviceRegistrationOutput::class,
        read: false,
        processor: DeviceRegistrationProcessor::class,
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

    #[Assert\Choice(choices: ['protected_person', 'caregiver'])]
    public string $deviceType = 'protected_person';
}
