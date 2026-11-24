<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

/**
 * Outcome counters of one notification round (initial dispatch, retry or
 * reminder) across the caregivers linked to the protected person.
 */
final readonly class NotificationRoundResult
{
    public function __construct(
        public int $linkedCaregivers = 0,
        public int $alreadySent = 0,
        public int $sent = 0,
        public int $transientFailures = 0,
        public int $invalidTokens = 0,
        public int $missingTokens = 0,
    ) {
    }

    /** Caregivers that have this round's push, including those reached in an earlier interrupted run. */
    public function delivered(): int
    {
        return $this->alreadySent + $this->sent;
    }

    /** @return array<string, int> */
    public function toLogContext(): array
    {
        return [
            'linkedCaregivers' => $this->linkedCaregivers,
            'alreadySent' => $this->alreadySent,
            'sent' => $this->sent,
            'transientFailures' => $this->transientFailures,
            'invalidTokens' => $this->invalidTokens,
            'missingTokens' => $this->missingTokens,
        ];
    }
}
