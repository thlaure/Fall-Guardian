<?php

declare(strict_types=1);

namespace App\Infrastructure\Sms;

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

final class FakeSmsStore
{
    public function __construct(
        private readonly string $projectDir,
        private readonly string $shareDir,
    ) {
    }

    /**
     * @return array<int, array{providerMessageId: string, to: string, body: string, createdAt: string}>
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

            if (
                is_array($decoded)
                && isset($decoded['providerMessageId'], $decoded['to'], $decoded['body'], $decoded['createdAt'])
                && is_string($decoded['providerMessageId'])
                && is_string($decoded['to'])
                && is_string($decoded['body'])
                && is_string($decoded['createdAt'])
            ) {
                /* @var array{providerMessageId: string, to: string, body: string, createdAt: string} $decoded */
                $entries[] = $decoded;
            }
        }

        return $entries;
    }

    public function append(string $providerMessageId, string $to, string $body): void
    {
        $path = $this->path();
        $directory = dirname($path);

        if (!is_dir($directory)) {
            mkdir($directory, 0777, true);
        }

        $entry = [
            'providerMessageId' => $providerMessageId,
            'to' => $to,
            'body' => $body,
            'createdAt' => (new DateTimeImmutable())->format(DATE_ATOM),
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
            '%s/%s/fake_sms_inbox.jsonl',
            $this->projectDir,
            rtrim($this->shareDir, '/'),
        );
    }
}
