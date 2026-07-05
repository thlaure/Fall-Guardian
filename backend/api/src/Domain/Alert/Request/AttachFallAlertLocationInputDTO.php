<?php

declare(strict_types=1);

namespace App\Domain\Alert\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Alert\Processor\AttachFallAlertLocationProcessor;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{clientAlertId}/location',
        output: FallAlertOutputDTO::class,
        read: false,
        openapi: new Operation(
            tags: ['Fall alerts'],
            summary: 'Attach a location fix to an already-reported fall alert',
            description: 'Updates the latitude/longitude of a fall alert once a GPS fix resolves. Reporting the alert must not block on this — it is submitted separately, best-effort. Only the protected-person device that reported the alert may attach a location.',
            security: [['deviceBearer' => []]],
        ),
        processor: AttachFallAlertLocationProcessor::class,
    ),
])]
final class AttachFallAlertLocationInputDTO
{
    #[Assert\Range(min: -90, max: 90)]
    public ?float $latitude = null;

    #[Assert\Range(min: -180, max: 180)]
    public ?float $longitude = null;
}
