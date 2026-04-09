<?php

declare(strict_types=1);

namespace App\Dto;

final class ReplaceContactsOutput
{
    public function __construct(
        public int $storedContacts,
    ) {
    }
}
