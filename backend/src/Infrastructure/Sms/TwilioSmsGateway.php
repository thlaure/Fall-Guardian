<?php

declare(strict_types=1);

namespace App\Infrastructure\Sms;

use App\Domain\Sms\Port\SmsGatewayInterface;

use function in_array;

use RuntimeException;
use Twilio\Rest\Client;

final readonly class TwilioSmsGateway implements SmsGatewayInterface
{
    public function __construct(
        private string $accountSid,
        private string $authToken,
        private string $from,
    ) {
    }

    public function getProviderName(): string
    {
        return 'twilio';
    }

    public function send(string $to, string $body): array
    {
        if (in_array('', [$this->accountSid, $this->authToken, $this->from], true)) {
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
