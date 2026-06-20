<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Processor\CreateInviteProcessor;
use DateTimeImmutable;
use DateTimeInterface;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/invites',
        input: false,
        output: self::class,
        read: false,
        openapi: new Operation(
            tags: ['Caregiver links'],
            summary: 'Create a caregiver invitation',
            description: 'Creates a short-lived invitation code on a protected-person device. Share the code with the caregiver who will accept the link.',
            security: [['deviceBearer' => []]],
        ),
        processor: CreateInviteProcessor::class,
    ),
])]
final class CreateInviteOutputDTO
{
    public string $code = '';

    public string $expiresAt = '';

    public static function fromInviteData(string $code, DateTimeImmutable $expiresAt): self
    {
        $output = new self();
        $output->code = $code;
        $output->expiresAt = $expiresAt->format(DateTimeInterface::ATOM);

        return $output;
    }
}
