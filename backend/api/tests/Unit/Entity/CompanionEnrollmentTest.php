<?php

declare(strict_types=1);

namespace App\Tests\Unit\Entity;

use App\Entity\CompanionEnrollment;
use App\Entity\Device;
use DateTimeImmutable;
use PHPUnit\Framework\TestCase;

final class CompanionEnrollmentTest extends TestCase
{
    public function testEnrollmentCanOnlyBeClaimedOnceBeforeExpiry(): void
    {
        $device = new Device('phone', 'hash', 'ios', '1.0.0');
        $protectedPerson = $device->getProtectedPerson();
        self::assertNotNull($protectedPerson);
        $now = new DateTimeImmutable('2026-07-25T10:00:00+00:00');
        $enrollment = new CompanionEnrollment(
            $protectedPerson,
            $device,
            str_repeat('a', 64),
            'watchos',
            $now->modify('+5 minutes'),
        );

        self::assertTrue($enrollment->claim($now));
        self::assertFalse($enrollment->claim($now->modify('+1 second')));
    }

    public function testExpiredEnrollmentCannotBeClaimed(): void
    {
        $device = new Device('phone', 'hash', 'ios', '1.0.0');
        $protectedPerson = $device->getProtectedPerson();
        self::assertNotNull($protectedPerson);
        $expiresAt = new DateTimeImmutable('2026-07-25T10:00:00+00:00');
        $enrollment = new CompanionEnrollment(
            $protectedPerson,
            $device,
            str_repeat('b', 64),
            'wearos',
            $expiresAt,
        );

        self::assertFalse($enrollment->claim($expiresAt));
    }
}
