<?php

declare(strict_types=1);

namespace App\Infrastructure\Sms;

use App\Application\SmsGateway;
use RuntimeException;
use Twilio\Rest\Client;

final class TwilioSmsGateway implements SmsGateway
{
    public function __construct(
        private readonly string $accountSid,
        private readonly string $authToken,
        private readonly string $from,
    ) {
    }

    public function getProviderName(): string
    {
        return 'twilio';
    }

    public function send(string $to, string $body): array
    {
        if ('' === $this->accountSid || '' === $this->authToken || '' === $this->from) {
            throw new RuntimeException('Twilio credentials are not configured.');
        }

        $client = new Client($this->accountSid, $this->authToken);
        $message = $client->messages->create($to, [
            'from' => $this->from,
            'body' => $body,
        ]);

        return [
            'providerMessageId' => $message->sid,
            'status' => (string) $message->status,
        ];
    }
}
