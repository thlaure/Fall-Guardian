<?php

declare(strict_types=1);

namespace App\Controller;

use App\Repository\SmsAttemptRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final class TwilioWebhookController
{
    public function __construct(
        private readonly SmsAttemptRepository $smsAttemptRepository,
        private readonly EntityManagerInterface $entityManager,
    ) {
    }

    #[Route('/webhooks/sms/twilio', name: 'app_twilio_webhook', methods: ['POST'])]
    public function __invoke(Request $request): Response
    {
        $messageSid = (string) $request->request->get('MessageSid', '');
        $messageStatus = (string) $request->request->get('MessageStatus', '');

        if ('' === $messageSid) {
            return new Response(status: Response::HTTP_NO_CONTENT);
        }

        $attempt = $this->smsAttemptRepository->findOneByProviderMessageId($messageSid);

        if (null === $attempt) {
            return new Response(status: Response::HTTP_NO_CONTENT);
        }

        if ('delivered' === $messageStatus) {
            $attempt->markDelivered();
            $this->entityManager->flush();
        }

        return new Response(status: Response::HTTP_NO_CONTENT);
    }
}
