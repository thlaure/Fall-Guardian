<?php

declare(strict_types=1);

namespace App\Domain\Push\Model;

/**
 * Data carried by a fall-alert push notification.
 *
 * The `data` map is a public contract with the caregiver app: existing keys
 * (`type`, `alertId`, `fallTimestamp`, `latitude`, `longitude`) must never be
 * renamed or removed; new keys may only be added.
 */
final readonly class FallAlertPushPayload
{
    public const string TYPE = 'fall_alert';

    public function __construct(
        public string $alertId,
        public string $fallTimestamp,
        public string $cancelDeadlineAt,
        public ?float $latitude = null,
        public ?float $longitude = null,
        public ?string $protectedPersonName = null,
        public bool $reminder = false,
    ) {
    }

    /** @return array<string, string> */
    public function toData(): array
    {
        $data = [
            'type' => self::TYPE,
            'alertId' => $this->alertId,
            'fallTimestamp' => $this->fallTimestamp,
            'cancelDeadlineAt' => $this->cancelDeadlineAt,
            'reminder' => $this->reminder ? '1' : '0',
        ];

        if (null !== $this->latitude) {
            $data['latitude'] = (string) $this->latitude;
        }

        if (null !== $this->longitude) {
            $data['longitude'] = (string) $this->longitude;
        }

        if (null !== $this->protectedPersonName) {
            $data['protectedPersonName'] = $this->protectedPersonName;
        }

        return $data;
    }
}
