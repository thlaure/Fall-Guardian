<?php

declare(strict_types=1);

namespace App\Application\Contact\Handler;

use RuntimeException;

use const SODIUM_CRYPTO_SECRETBOX_NONCEBYTES;

use function sprintf;
use function strlen;

final readonly class ContactCryptoService
{
    private string $encryptionKey;

    private string $hashKey;

    public function __construct(string $encryptionSecret, string $hashSecret)
    {
        $this->encryptionKey = hash('sha256', $encryptionSecret, true);
        $this->hashKey = hash('sha256', $hashSecret, true);
    }

    public function encrypt(string $phoneNumber): string
    {
        $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $ciphertext = sodium_crypto_secretbox($phoneNumber, $nonce, $this->encryptionKey);

        return base64_encode($nonce . $ciphertext);
    }

    public function decrypt(string $ciphertext): string
    {
        $decoded = base64_decode($ciphertext, true);

        if (false === $decoded || strlen($decoded) <= SODIUM_CRYPTO_SECRETBOX_NONCEBYTES) {
            throw new RuntimeException('Invalid ciphertext payload.');
        }

        $nonce = substr($decoded, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $payload = substr($decoded, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        $plain = sodium_crypto_secretbox_open($payload, $nonce, $this->encryptionKey);

        if (false === $plain) {
            throw new RuntimeException('Unable to decrypt phone number.');
        }

        return $plain;
    }

    public function hash(string $phoneNumber): string
    {
        return hash_hmac('sha256', $phoneNumber, $this->hashKey);
    }

    public function last4(string $phoneNumber): string
    {
        return substr(preg_replace('/\D/', '', $phoneNumber) ?? '', -4) ?: '0000';
    }

    public function mask(string $phoneLast4): string
    {
        return sprintf('***%s', $phoneLast4);
    }
}
