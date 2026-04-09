<?php

declare(strict_types=1);

namespace App\Security;

final class DeviceTokenHasher
{
    public function hash(string $plainToken): string
    {
        return hash('sha256', $plainToken);
    }

    public function generatePlainToken(): string
    {
        return bin2hex(random_bytes(32));
    }
}
