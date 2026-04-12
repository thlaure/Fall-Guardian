<?php

declare(strict_types=1);

namespace App\Application\Contact\DTO;

final class ReplaceContactsOutput
{
    public function __construct(
        public int $storedContacts,
    ) {
    }
}
