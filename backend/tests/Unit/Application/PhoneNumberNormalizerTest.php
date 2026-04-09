<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\PhoneNumberNormalizer;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class PhoneNumberNormalizerTest extends TestCase
{
    #[Test]
    public function it_normalizes_french_numbers_to_e164(): void
    {
        $normalizer = new PhoneNumberNormalizer('+33');

        self::assertSame('+33612345678', $normalizer->normalize('06 12 34 56 78'));
    }
}
