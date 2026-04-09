<?php

declare(strict_types=1);

namespace App\Api;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Put;
use App\Dto\ContactInput;
use App\Dto\ReplaceContactsOutput;
use App\State\ReplaceContactsProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Put(
        uriTemplate: '/api/v1/emergency-contacts',
        output: ReplaceContactsOutput::class,
        processor: ReplaceContactsProcessor::class,
        read: false,
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
