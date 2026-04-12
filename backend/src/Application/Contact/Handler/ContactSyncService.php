<?php

declare(strict_types=1);

namespace App\Application\Contact\Handler;

use App\Domain\Contact\Port\EmergencyContactRepositoryInterface;
use App\Entity\Device;
use App\Entity\EmergencyContact;

use function count;

use Doctrine\ORM\EntityManagerInterface;

final readonly class ContactSyncService
{
    public function __construct(
        private EmergencyContactRepositoryInterface $contactRepository,
        private PhoneNumberNormalizer $phoneNumberNormalizer,
        private ContactCryptoService $contactCryptoService,
        private EntityManagerInterface $entityManager,
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
