<?php

declare(strict_types=1);

namespace App\Domain\Alert\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Alert\Processor\CreateFallAlertProcessor;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use DateTimeImmutable;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts',
        output: FallAlertOutputDTO::class,
        read: false,
        openapi: new Operation(
            tags: ['Fall alerts'],
            summary: 'Report a detected fall',
            description: 'Reports a fall detected for the authenticated protected-person device. Use a stable clientAlertId to identify this alert across retries and later cancellation.',
            security: [['deviceBearer' => []]],
        ),
        processor: CreateFallAlertProcessor::class,
    ),
])]
final class CreateFallAlertInputDTO
{
    #[Assert\NotBlank]
    #[Assert\Length(max: 100)]
    public string $clientAlertId = '';

    #[Assert\NotNull]
    public ?DateTimeImmutable $fallTimestamp = null;

    #[Assert\NotBlank]
    #[Assert\Length(max: 8)]
    public string $locale = 'en';

    #[Assert\Range(min: -90, max: 90)]
    public ?float $latitude = null;

    #[Assert\Range(min: -180, max: 180)]
    public ?float $longitude = null;

    #[Assert\Type('bool')]
    public bool $cancelled = false;
}
