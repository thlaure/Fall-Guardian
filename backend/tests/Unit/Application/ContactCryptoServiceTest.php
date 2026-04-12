<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\Contact\Handler\ContactCryptoService;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class ContactCryptoServiceTest extends TestCase
{
    #[Test]
    public function itEncryptsAndDecryptsPhoneNumbers(): void
    {
        $service = new ContactCryptoService('encryption-secret', 'hash-secret');
        $phone = '+33612345678';

        $ciphertext = $service->encrypt($phone);

        self::assertNotSame($phone, $ciphertext);
        self::assertSame($phone, $service->decrypt($ciphertext));
    }
}
