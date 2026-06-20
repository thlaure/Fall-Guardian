<?php

declare(strict_types=1);

namespace App\Domain\Device\Response;

final class DeviceRegistrationOutputDTO
{
    public function __construct(
        public string $deviceId,
        public string $deviceToken,
    ) {
    }
}
