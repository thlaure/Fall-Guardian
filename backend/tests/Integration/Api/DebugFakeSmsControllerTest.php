<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use App\Infrastructure\Sms\FakeSmsGateway;

use function json_decode;

use const JSON_THROW_ON_ERROR;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

final class DebugFakeSmsControllerTest extends WebTestCase
{
    public function testFakeSmsInboxEndpointReturnsStoredMessages(): void
    {
        $client = self::createClient();

        /** @var \App\Infrastructure\Sms\FakeSmsStore $store */
        $store = self::getContainer()->get(\App\Infrastructure\Sms\FakeSmsStore::class);
        $store->clear();

        $gateway = self::getContainer()->get(FakeSmsGateway::class);
        $gateway->send('+33612345678', 'Hello fake SMS');

        $client->request(\Symfony\Component\HttpFoundation\Request::METHOD_GET, '/debug/fake-sms');

        self::assertResponseIsSuccessful();

        /** @var array{provider?: string, messages?: list<array{to?: string, body?: string}>} $payload */
        $payload = json_decode($client->getResponse()->getContent() ?: '', true, 512, JSON_THROW_ON_ERROR);

        self::assertSame('fake', $payload['provider'] ?? null);
        self::assertCount(1, $payload['messages'] ?? []);
        self::assertSame('+33612345678', $payload['messages'][0]['to'] ?? null);
        self::assertSame('Hello fake SMS', $payload['messages'][0]['body'] ?? null);
    }
}
