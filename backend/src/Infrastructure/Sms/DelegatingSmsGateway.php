<?php

declare(strict_types=1);

namespace App\Infrastructure\Sms;

use App\Domain\Sms\Port\SmsGatewayInterface;
use InvalidArgumentException;

use function sprintf;

final readonly class DelegatingSmsGateway implements SmsGatewayInterface
{
    public function __construct(
        private string $provider,
        private TwilioSmsGateway $twilioSmsGateway,
        private FakeSmsGateway $fakeSmsGateway,
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

    private function inner(): SmsGatewayInterface
    {
        return match ($this->provider) {
            'twilio' => $this->twilioSmsGateway,
            'fake' => $this->fakeSmsGateway,
            default => throw new InvalidArgumentException(sprintf('Unsupported SMS provider "%s".', $this->provider)),
        };
    }
}
