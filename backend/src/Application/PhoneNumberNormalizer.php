<?php

declare(strict_types=1);

namespace App\Application;

use InvalidArgumentException;

final class PhoneNumberNormalizer
{
    public function __construct(private readonly string $defaultCountryCode)
    {
    }

    public function normalize(string $rawPhone): string
    {
        $normalized = preg_replace('/[^\d+]/', '', trim($rawPhone));

        if (null === $normalized || '' === $normalized) {
            throw new InvalidArgumentException('Phone number is required.');
        }

        if (str_starts_with($normalized, '00')) {
            $normalized = '+' . substr($normalized, 2);
        }

        if (str_starts_with($normalized, '0')) {
            $normalized = $this->defaultCountryCode . substr($normalized, 1);
        }

        if (!str_starts_with($normalized, '+')) {
            $normalized = $this->defaultCountryCode . ltrim($normalized, '+');
        }

        if (!preg_match('/^\+[1-9]\d{7,14}$/', $normalized)) {
            throw new InvalidArgumentException('Phone number must be a valid E.164 number.');
        }

        return $normalized;
    }
}
