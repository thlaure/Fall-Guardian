<?php

declare(strict_types=1);

namespace App\Domain\Push\Exception;

/**
 * The provider rejected this message for a reason a retry will not fix
 * (malformed payload, forbidden sender, unknown project...). The attempt is
 * final, but the device token is NOT known to be dead and must be kept.
 */
final class PermanentPushDeliveryException extends PushDeliveryException
{
}
