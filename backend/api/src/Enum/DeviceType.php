<?php

declare(strict_types=1);

namespace App\Enum;

enum DeviceType: string
{
    case ProtectedPerson = 'protected_person';
    case Caregiver = 'caregiver';
}
