<?php

declare(strict_types=1);

namespace App\Application\Alert\Handler;

use App\Application\Contact\Handler\AlertMessageBuilder;
use App\Application\Contact\Handler\ContactCryptoService;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Contact\Port\EmergencyContactRepositoryInterface;
use App\Domain\Sms\Port\SmsGatewayInterface;
use App\Entity\FallAlert;
use App\Entity\SmsAttempt;
use App\Message\SendFallAlertMessage;

use function count;

use DateTimeImmutable;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Throwable;

#[AsMessageHandler]
final readonly class SendFallAlertMessageHandler
{
    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private EmergencyContactRepositoryInterface $contactRepository,
        private ContactCryptoService $contactCryptoService,
        private SmsGatewayInterface $smsGateway,
        private AlertMessageBuilder $messageBuilder,
        private EntityManagerInterface $entityManager,
    ) {
    }

    public function __invoke(SendFallAlertMessage $message): void
    {
        $alert = $this->fallAlertRepository->findById($message->fallAlertId);

        if (!$alert instanceof FallAlert || $alert->getCancelledAt() instanceof DateTimeImmutable) {
            return;
        }

        $alert->markDispatching();
        $body = $this->messageBuilder->build($alert);
        $contacts = $this->contactRepository->findByDevice($alert->getDevice());

        if ([] === $contacts) {
            $alert->markFailed();
            $this->fallAlertRepository->save($alert);

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
