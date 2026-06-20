<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Message;

final readonly class NotifyCaregiverLinkRevokedMessage
{
    public function __construct(public string $caregiverDeviceId)
    {
    }
}
