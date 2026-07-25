<?php

declare(strict_types=1);

namespace App\Enum;

enum FallDetectionSource: string
{
    case AssistedPhone = 'assisted_phone';
    case AppleWatch = 'apple_watch';
    case WearOs = 'wear_os';
}
