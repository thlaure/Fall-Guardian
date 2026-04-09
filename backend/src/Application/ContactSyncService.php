<?php

declare(strict_types=1);

namespace App\Application;

use App\Entity\Device;
use App\Entity\EmergencyContact;
use App\Repository\EmergencyContactRepository;
use Doctrine\ORM\EntityManagerInterface;

final class ContactSyncService
{
    public function __construct(
        private readonly EmergencyContactRepository $contactRepository,
        private readonly PhoneNumberNormalizer $phoneNumberNormalizer,
        private readonly ContactCryptoService $contactCryptoService,
        private readonly EntityManagerInterface $entityManager,
    ) {
    }

    /** @param list<array{id: string, name: string, phone: string}> $contacts */
    public function replaceContacts(Device $device, array $contacts): int
    {
        $seenHashes = [];
        $this->contactRepository->deleteForDevice($device);

        foreach ($contacts as $index => $contact) {
            $normalizedPhone = $this->phoneNumberNormalizer->normalize($contact['phone']);
            $phoneHash = $this->contactCryptoService->hash($normalizedPhone);

            if (isset($seenHashes[$phoneHash])) {
                continue;
            }

            $seenHashes[$phoneHash] = true;

            $this->entityManager->persist(new EmergencyContact(
                $device,
                trim($contact['name']),
                $this->contactCryptoService->encrypt($normalizedPhone),
                $phoneHash,
                $this->contactCryptoService->last4($normalizedPhone),
                $index,
            ));
        }

        $this->entityManager->flush();

        return count($seenHashes);
    }
}
