<?php

declare(strict_types=1);

namespace App\UI\Controller;

use App\Domain\Alert\Port\SmsAttemptRepositoryInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final readonly class TwilioWebhookController
{
    public function __construct(
        private SmsAttemptRepositoryInterface $smsAttemptRepository,
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

        if (!$attempt instanceof \App\Entity\SmsAttempt) {
            return new Response(status: Response::HTTP_NO_CONTENT);
        }

        if ('delivered' === $messageStatus) {
            $attempt->markDelivered();
            $this->smsAttemptRepository->save($attempt);
        }

        return new Response(status: Response::HTTP_NO_CONTENT);
    }
}
