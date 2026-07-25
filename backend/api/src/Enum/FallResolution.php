<?php

declare(strict_types=1);

namespace App\Enum;

enum FallResolution: string
{
    case Unknown = 'unknown';
    case Confirmed = 'confirmed';
    case Dismissed = 'dismissed';
    case Unresponsive = 'unresponsive';
    case Rejected = 'rejected';
}
