<?php

declare(strict_types=1);

namespace App\Enum;

enum FallAlertStatus: string
{
    case Received = 'received';
    case Dispatching = 'dispatching';
    case Sent = 'sent';
    case PartiallySent = 'partially_sent';
    case Failed = 'failed';
    case Cancelled = 'cancelled';
}
