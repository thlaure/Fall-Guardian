<?php

declare(strict_types=1);

namespace App\Tests\Unit\Shared;

use App\Shared\DateTime\ApiDateTimeFormatter;
use DateTimeImmutable;
use DateTimeZone;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class ApiDateTimeFormatterTest extends TestCase
{
    #[Test]
    public function itFormatsStoredUtcTimestampWithoutApplyingLocalTimezoneOffset(): void
    {
        $storedUtcWallClock = new DateTimeImmutable('2026-06-21 07:10:11', new DateTimeZone('Europe/Paris'));

        self::assertSame(
            '2026-06-21T07:10:11+00:00',
            ApiDateTimeFormatter::formatUtc($storedUtcWallClock),
        );
    }

    #[Test]
    public function itNormalizesIncomingInstantToUtcBeforeStorage(): void
    {
        $parisInstant = new DateTimeImmutable('2026-06-21T09:10:11+02:00');

        self::assertSame(
            '2026-06-21 07:10:11',
            ApiDateTimeFormatter::normalizeToUtc($parisInstant)->format('Y-m-d H:i:s'),
        );
    }
}
