<?php

declare(strict_types=1);

namespace App\Infrastructure\Sms;

use App\Application\SmsGateway;
use InvalidArgumentException;

use function sprintf;

final class DelegatingSmsGateway implements SmsGateway
{
    public function __construct(
        private readonly string $provider,
        private readonly TwilioSmsGateway $twilioSmsGateway,
        private readonly FakeSmsGateway $fakeSmsGateway,
    ) {
    }

    public function getProviderName(): string
    {
        return $this->inner()->getProviderName();
    }

    public function send(string $to, string $body): array
    {
        return $this->inner()->send($to, $body);
    }

    private function inner(): SmsGateway
    {
        return match ($this->provider) {
            'twilio' => $this->twilioSmsGateway,
            'fake' => $this->fakeSmsGateway,
            default => throw new InvalidArgumentException(sprintf('Unsupported SMS provider "%s".', $this->provider)),
        };
    }
}
