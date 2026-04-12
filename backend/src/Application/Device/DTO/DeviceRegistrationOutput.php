<?php

declare(strict_types=1);

namespace App\Application\Device\DTO;

final class DeviceRegistrationOutput
{
    public function __construct(
        public string $deviceId,
        public string $deviceToken,
    ) {
    }
}
