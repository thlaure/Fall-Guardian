<?php

declare(strict_types=1);

namespace App\Domain\Companion\Service;

use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Entity\CompanionEnrollment;
use App\Entity\Device;

interface CompanionEnrollmentServiceInterface
{
    /** @return array{token: string, enrollment: CompanionEnrollment} */
    public function create(Device $device, string $platform): array;

    public function claim(string $token, string $platform, string $appVersion): DeviceRegistrationOutputDTO;
}
