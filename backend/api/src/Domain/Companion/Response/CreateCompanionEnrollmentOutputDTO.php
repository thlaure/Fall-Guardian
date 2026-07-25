<?php

declare(strict_types=1);

namespace App\Domain\Companion\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Companion\Processor\CreateCompanionEnrollmentProcessor;
use App\Domain\Companion\Request\CreateCompanionEnrollmentInputDTO;
use DateTimeImmutable;
use DateTimeInterface;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/companion-enrollments',
        input: CreateCompanionEnrollmentInputDTO::class,
        output: self::class,
        read: false,
        openapi: new Operation(
            tags: ['Companion devices'],
            summary: 'Create a short-lived companion enrollment',
            security: [['deviceBearer' => []]],
        ),
        processor: CreateCompanionEnrollmentProcessor::class,
    ),
])]
final class CreateCompanionEnrollmentOutputDTO
{
    public function __construct(
        public string $enrollmentToken,
        public string $expiresAt,
    ) {
    }

    public static function create(string $token, DateTimeImmutable $expiresAt): self
    {
        return new self($token, $expiresAt->format(DateTimeInterface::ATOM));
    }
}
