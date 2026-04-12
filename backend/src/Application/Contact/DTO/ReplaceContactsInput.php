<?php

declare(strict_types=1);

namespace App\Application\Contact\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Put;
use App\UI\State\ReplaceContactsProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Put(
        uriTemplate: '/api/v1/emergency-contacts',
        output: ReplaceContactsOutput::class,
        read: false,
        processor: ReplaceContactsProcessor::class,
    ),
])]
final class ReplaceContactsInput
{
    /** @var list<ContactInput> */
    #[Assert\NotNull]
    #[Assert\Count(max: 10)]
    #[Assert\Valid]
    public array $contacts = [];
}
