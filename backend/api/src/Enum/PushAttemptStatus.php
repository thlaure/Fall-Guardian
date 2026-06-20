<?php

declare(strict_types=1);

namespace App\Enum;

enum PushAttemptStatus: string
{
    case Queued = 'queued';
    case Sent = 'sent';
    case Failed = 'failed';
}
