<?php

declare(strict_types=1);

namespace App\Application\Contact\DTO;

use Symfony\Component\Validator\Constraints as Assert;

final class ContactInput
{
    #[Assert\NotBlank]
    public string $id = '';

    #[Assert\NotBlank]
    #[Assert\Length(max: 100)]
    public string $name = '';

    #[Assert\NotBlank]
    #[Assert\Length(max: 32)]
    public string $phone = '';
}
