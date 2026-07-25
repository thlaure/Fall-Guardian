<?php

declare(strict_types=1);

namespace App\Tests\Unit\Entity;

use App\Entity\Device;
use App\Enum\DeviceType;
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
}
