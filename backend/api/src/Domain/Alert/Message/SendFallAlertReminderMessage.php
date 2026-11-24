<?php

declare(strict_types=1);

namespace App\Domain\Alert\Message;

final readonly class SendFallAlertReminderMessage
{
    /** @param int $reminderNumber 1-based reminder number, already reserved on the alert */
    public function __construct(
        public string $fallAlertId,
        public int $reminderNumber,
    ) {
    }
}
