<?php

declare(strict_types=1);

namespace App\Domain\Device\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Device\Processor\DeviceRegistrationProcessor;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/devices/register',
        output: DeviceRegistrationOutputDTO::class,
        read: false,
        openapi: new Operation(
            tags: ['Devices'],
            summary: 'Register a device',
            description: 'Registers an app installation and returns the bearer token required by subsequent API calls. Store that token securely on the device.',
        ),
        processor: DeviceRegistrationProcessor::class,
    ),
])]
final class DeviceRegistrationInputDTO
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
