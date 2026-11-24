<?php

declare(strict_types=1);

namespace App\Tests\Unit\Entity;

use App\Entity\Device;
use App\Enum\DeviceType;
use DateTimeImmutable;
use PHPUnit\Framework\TestCase;

final class DeviceTest extends TestCase
{
    public function testProtectedDeviceGetsStableIdentityAndCompanionCanShareIt(): void
    {
        $phone = new Device('phone', 'phone-hash', 'ios', '1.0.0');
        $watch = new Device('watch', 'watch-hash', 'watchos', '1.0.0');

        $protectedPerson = $phone->getProtectedPerson();
        self::assertNotNull($protectedPerson);

        $watch->attachToProtectedPerson($protectedPerson);

        self::assertSame($protectedPerson, $watch->getProtectedPerson());
        self::assertSame(DeviceType::ProtectedPerson, $watch->getDeviceType());
    }

    public function testCaregiverHasNoProtectedPersonIdentity(): void
    {
        $device = new Device('caregiver', 'caregiver-hash', 'android', '1.0.0');

        $device->setDeviceType(DeviceType::Caregiver);

        self::assertNull($device->getProtectedPerson());
    }

    public function testLastSeenIsRecordedAtMostOncePerResolutionWindow(): void
    {
        $device = new Device('device', 'hash', 'ios', '1.0.0');
        $first = new DateTimeImmutable('2026-07-23T08:00:00+00:00');

        self::assertTrue($device->touchSeenAt($first));
        self::assertFalse($device->touchSeenAt($first->modify('+299 seconds')));
        self::assertSame($first, $device->getLastSeenAt());
        self::assertTrue($device->touchSeenAt($first->modify('+300 seconds')));
        self::assertEquals($first->modify('+300 seconds'), $device->getLastSeenAt());
    }
}
