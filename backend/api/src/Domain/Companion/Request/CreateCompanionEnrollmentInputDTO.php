<?php

declare(strict_types=1);

namespace App\Domain\Companion\Request;

use Symfony\Component\Validator\Constraints as Assert;

final class CreateCompanionEnrollmentInputDTO
{
    #[Assert\Choice(choices: ['watchos', 'wearos'])]
    public string $platform = '';
}
