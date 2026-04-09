<?php

declare(strict_types=1);

namespace App\MessageHandler;

use App\Application\AlertMessageBuilder;
use App\Application\ContactCryptoService;
use App\Application\SmsGateway;
use App\Entity\FallAlert;
use App\Entity\SmsAttempt;
use App\Message\SendFallAlertMessage;
use App\Repository\EmergencyContactRepository;

use function count;

use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\Uid\Uuid;
use Throwable;

#[AsMessageHandler]
final class SendFallAlertMessageHandler
{
    public function __construct(
        private readonly EntityManagerInterface $entityManager,
        private readonly EmergencyContactRepository $contactRepository,
        private readonly ContactCryptoService $contactCryptoService,
        private readonly SmsGateway $smsGateway,
        private readonly AlertMessageBuilder $messageBuilder,
    ) {
    }

    public function __invoke(SendFallAlertMessage $message): void
    {
        $alert = $this->entityManager->find(FallAlert::class, Uuid::fromString($message->fallAlertId));

        if (!$alert instanceof FallAlert || null !== $alert->getCancelledAt()) {
            return;
        }

        $alert->markDispatching();
        $body = $this->messageBuilder->build($alert);
        $contacts = $this->contactRepository->findByDevice($alert->getDevice());

        if ([] === $contacts) {
            $alert->markFailed();
            $this->entityManager->flush();

            return;
        }

        $sentCount = 0;
        $provider = $this->smsGateway->getProviderName();
        foreach ($contacts as $contact) {
            $attempt = new SmsAttempt($alert, $contact, $provider);
            $alert->addSmsAttempt($attempt);
            $this->entityManager->persist($attempt);

            try {
                $result = $this->smsGateway->send(
                    $this->contactCryptoService->decrypt($contact->getPhoneCiphertext()),
                    $body,
                );
                $attempt->markSent($result['providerMessageId']);
                ++$sentCount;
            } catch (Throwable $exception) {
                $attempt->markFailed((string) $exception->getCode(), $exception->getMessage());
            }
        }

        if (0 === $sentCount) {
            $alert->markFailed();
        } elseif ($sentCount === count($contacts)) {
            $alert->markSent();
        } else {
            $alert->markPartiallySent();
        }

        $this->entityManager->flush();
    }
}
