<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use const DATE_ATOM;

use DateTimeImmutable;

use function dirname;
use function explode;

use const FILE_APPEND;

use function file_exists;
use function file_get_contents;
use function file_put_contents;
use function is_array;
use function is_dir;
use function is_string;
use function json_decode;
use function json_encode;

use const JSON_THROW_ON_ERROR;

use function mkdir;
use function rtrim;
use function sprintf;
use function trim;

final readonly class FakePushStore
{
    public function __construct(
        private string $projectDir,
        private string $shareDir,
    ) {
    }

    /**
     * @return array<int, array{providerMessageId: string, fcmToken: string, alertId: string, fallTimestamp: string, latitude: string|null, longitude: string|null, createdAt: string}>
     */
    public function all(): array
    {
        $path = $this->path();

        if (!file_exists($path)) {
            return [];
        }

        $entries = [];
        $contents = file_get_contents($path);

        if (false === $contents || '' === $contents) {
            return [];
        }

        foreach (explode("\n", trim($contents)) as $line) {
            if ('' === $line) {
                continue;
            }

            $decoded = json_decode($line, true, 512, JSON_THROW_ON_ERROR);

            if (!is_array($decoded)) {
                continue;
            }

            $providerMessageId = $decoded['providerMessageId'] ?? null;
            $fcmToken = $decoded['fcmToken'] ?? null;
            $alertId = $decoded['alertId'] ?? null;
            $fallTimestamp = $decoded['fallTimestamp'] ?? null;
            $createdAt = $decoded['createdAt'] ?? null;

            if (
                is_string($providerMessageId)
                && is_string($fcmToken)
                && is_string($alertId)
                && is_string($fallTimestamp)
                && is_string($createdAt)
            ) {
                $latitude = isset($decoded['latitude']) && is_string($decoded['latitude']) ? $decoded['latitude'] : null;
                $longitude = isset($decoded['longitude']) && is_string($decoded['longitude']) ? $decoded['longitude'] : null;

                $entries[] = [
                    'providerMessageId' => $providerMessageId,
                    'fcmToken' => $fcmToken,
                    'alertId' => $alertId,
                    'fallTimestamp' => $fallTimestamp,
                    'latitude' => $latitude,
                    'longitude' => $longitude,
                    'createdAt' => $createdAt,
                ];
            }
        }

        return $entries;
    }

    public function clear(): void
    {
        $path = $this->path();

        if (file_exists($path)) {
            file_put_contents($path, '');
        }
    }

    public function append(string $providerMessageId, string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): void
    {
        $path = $this->path();
        $directory = dirname($path);

        if (!is_dir($directory)) {
            mkdir($directory, 0777, true);
        }

        $entry = [
            'providerMessageId' => $providerMessageId,
            'fcmToken' => $fcmToken,
            'alertId' => $alertId,
            'fallTimestamp' => $fallTimestamp,
            'latitude' => null !== $latitude ? (string) $latitude : null,
            'longitude' => null !== $longitude ? (string) $longitude : null,
            'createdAt' => new DateTimeImmutable()->format(DATE_ATOM),
        ];

        file_put_contents(
            $path,
            sprintf("%s\n", json_encode($entry, JSON_THROW_ON_ERROR)),
            FILE_APPEND,
        );
    }

    private function path(): string
    {
        return sprintf(
            '%s/%s/fake_push_inbox.jsonl',
            $this->projectDir,
            rtrim($this->shareDir, '/'),
        );
    }
}
