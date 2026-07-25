<?php

declare(strict_types=1);

namespace App\Domain\Companion\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Companion\Processor\ClaimCompanionEnrollmentProcessor;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/companion-enrollments/claim',
        output: DeviceRegistrationOutputDTO::class,
        read: false,
        openapi: new Operation(
            tags: ['Companion devices'],
            summary: 'Exchange a one-time enrollment token for companion credentials',
        ),
        processor: ClaimCompanionEnrollmentProcessor::class,
    ),
])]
final class ClaimCompanionEnrollmentInputDTO
{
    #[Assert\NotBlank]
    #[Assert\Length(min: 64, max: 64)]
    public string $enrollmentToken = '';

    #[Assert\Choice(choices: ['watchos', 'wearos'])]
    public string $platform = '';

    #[Assert\NotBlank]
    #[Assert\Length(max: 32)]
    public string $appVersion = '';
}
