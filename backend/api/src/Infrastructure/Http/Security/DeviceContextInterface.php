<?php

declare(strict_types=1);

namespace App\Infrastructure\Http\Security;

use App\Entity\Device;

interface DeviceContextInterface
{
    public function requireDevice(): Device;
}
