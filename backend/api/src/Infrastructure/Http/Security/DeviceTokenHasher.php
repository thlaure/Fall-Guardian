<?php

declare(strict_types=1);

namespace App\Infrastructure\Http\Security;

final readonly class DeviceTokenHasher
{
    public function __construct(private string $secret)
    {
    }

    public function hash(string $plainToken): string
    {
        return hash_hmac('sha256', $plainToken, $this->secret);
    }

    /**
     * Temporary transition shim for devices registered before HMAC hashing.
     */
    public function legacyHash(string $plainToken): string
    {
        return hash('sha256', $plainToken);
    }

    public function generatePlainToken(): string
    {
        return bin2hex(random_bytes(32));
    }
}
