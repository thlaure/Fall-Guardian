<?php

declare(strict_types=1);

namespace App\Domain\Push\Exception;

/**
 * The provider could not deliver right now (HTTP 5xx, 429, timeout, transport
 * or OAuth token failure). Delivery to the same token may be retried later.
 */
final class TransientPushDeliveryException extends PushDeliveryException
{
}
