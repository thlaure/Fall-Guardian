<?php

declare(strict_types=1);

namespace App\Message;

final readonly class SendFallAlertPushMessage
{
    public function __construct(public string $fallAlertId)
    {
    }
}
