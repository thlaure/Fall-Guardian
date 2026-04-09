<?php

declare(strict_types=1);

namespace App\Enum;

enum SmsAttemptStatus: string
{
    case Queued = 'queued';
    case Sent = 'sent';
    case Delivered = 'delivered';
    case Failed = 'failed';
}
