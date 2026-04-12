<?php

declare(strict_types=1);

namespace App\Application\Contact\Handler;

use App\Entity\FallAlert;

use const DATE_ATOM;

use function sprintf;

final class AlertMessageBuilder
{
    public function build(FallAlert $alert): string
    {
        $location = null;

        if (null !== $alert->getLatitude() && null !== $alert->getLongitude()) {
            $location = sprintf(
                'Location: https://maps.google.com/?q=%s,%s',
                $alert->getLatitude(),
                $alert->getLongitude(),
            );
        }

        $parts = [
            'FALL ALERT: A possible fall was detected.',
            sprintf('Detected at: %s', $alert->getFallDetectedAt()->format(DATE_ATOM)),
            $location ?? 'Location unavailable.',
            'Please call or check on them immediately.',
            'Fall Guardian',
        ];

        return implode("\n", array_filter($parts));
    }
}
