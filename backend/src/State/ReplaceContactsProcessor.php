<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Api\ReplaceContactsInput;
use App\Application\ContactSyncService;
use App\Dto\ContactInput;
use App\Dto\ReplaceContactsOutput;
use App\Security\CurrentDeviceProvider;

/**
 * @implements ProcessorInterface<ReplaceContactsInput, ReplaceContactsOutput>
 */
final class ReplaceContactsProcessor implements ProcessorInterface
{
    public function __construct(
        private readonly ContactSyncService $contactSyncService,
        private readonly CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): ReplaceContactsOutput
    {
        \assert($data instanceof ReplaceContactsInput);

        $storedContacts = $this->contactSyncService->replaceContacts(
            $this->currentDeviceProvider->requireDevice(),
            array_map(fn (mixed $contact): array => $this->normalizeContact($contact), $data->contacts),
        );

        return new ReplaceContactsOutput($storedContacts);
    }

    /** @return array{id: string, name: string, phone: string} */
    private function normalizeContact(mixed $contact): array
    {
        if ($contact instanceof ContactInput) {
            return [
                'id' => $contact->id,
                'name' => $contact->name,
                'phone' => $contact->phone,
            ];
        }

        if (is_array($contact)) {
            return [
                'id' => $this->stringValue($contact['id'] ?? null),
                'name' => $this->stringValue($contact['name'] ?? null),
                'phone' => $this->stringValue($contact['phone'] ?? null),
            ];
        }

        throw new \InvalidArgumentException('Unsupported contact payload.');
    }

    private function stringValue(mixed $value): string
    {
        if (is_string($value)) {
            return $value;
        }

        if (is_int($value) || is_float($value) || is_bool($value)) {
            return (string) $value;
        }

        return '';
    }
}
