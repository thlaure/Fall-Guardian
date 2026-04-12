<?php

declare(strict_types=1);

namespace App\Application\Caregiver\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\UI\State\CreateInviteProcessor;
use DateTimeImmutable;
use DateTimeInterface;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/invites',
        output: self::class,
        read: false,
        processor: CreateInviteProcessor::class,
    ),
])]
final class CreateInviteOutput
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
