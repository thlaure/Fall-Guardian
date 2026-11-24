<?php

declare(strict_types=1);

namespace App\Domain\Push\Exception;

use RuntimeException;
use Throwable;

/**
 * Base class for push delivery failures. Messages must never contain push
 * tokens, coordinates, names, or raw provider response bodies.
 */
abstract class PushDeliveryException extends RuntimeException
{
    public function __construct(string $message, private readonly string $reason, ?Throwable $previous = null)
    {
        parent::__construct($message, 0, $previous);
    }

    /** Short machine-readable reason (e.g. "http_503", "UNREGISTERED", "transport"). */
    public function getReason(): string
    {
        return $this->reason;
    }
}
