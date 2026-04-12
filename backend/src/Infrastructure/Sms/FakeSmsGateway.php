<?php

declare(strict_types=1);

namespace App\Infrastructure\Sms;

use App\Domain\Sms\Port\SmsGatewayInterface;

use function sprintf;

use Symfony\Component\Uid\Uuid;

final readonly class FakeSmsGateway implements SmsGatewayInterface
{
    public function __construct(private FakeSmsStore $store)
    {
    }

    public function getProviderName(): string
    {
        return 'fake';
    }

    public function send(string $to, string $body): array
    {
        $providerMessageId = sprintf('fake-%s', Uuid::v7()->toRfc4122());
        $this->store->append($providerMessageId, $to, $body);

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }
}
