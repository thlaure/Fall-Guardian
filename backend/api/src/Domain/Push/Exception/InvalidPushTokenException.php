<?php

declare(strict_types=1);

namespace App\Domain\Push\Exception;

/**
 * The provider permanently rejected the device push token (unregistered,
 * invalid, or belonging to another sender). The token must not be retried and
 * should be removed.
 */
final class InvalidPushTokenException extends PushDeliveryException
{
}
