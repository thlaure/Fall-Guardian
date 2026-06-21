<?php

declare(strict_types=1);

namespace App\Shared\DateTime;

use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;

final readonly class ApiDateTimeFormatter
{
    private const string UTC_TIMEZONE = 'UTC';

    public static function normalizeToUtc(DateTimeImmutable $dateTime): DateTimeImmutable
    {
        return $dateTime->setTimezone(new DateTimeZone(self::UTC_TIMEZONE));
    }

    public static function formatUtc(DateTimeInterface $dateTime): string
    {
        return $dateTime->format('Y-m-d\TH:i:s').'+00:00';
    }
}
