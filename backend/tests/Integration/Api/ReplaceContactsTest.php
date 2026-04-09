<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use const JSON_THROW_ON_ERROR;

use function sprintf;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

final class ReplaceContactsTest extends WebTestCase
{
    public function testContactsCanBeSyncedAfterDeviceRegistration(): void
    {
        $client = static::createClient();

        $client->request('POST', '/api/v1/devices/register', server: [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_ACCEPT' => 'application/json',
        ], content: json_encode([
            'platform' => 'ios',
            'appVersion' => '1.0.0',
        ], JSON_THROW_ON_ERROR));

        self::assertResponseStatusCodeSame(201);

        $payload = json_decode($client->getResponse()->getContent() ?: '', true, 512, JSON_THROW_ON_ERROR);

        self::assertIsArray($payload);

        $token = $payload['deviceToken'] ?? null;

        self::assertIsString($token);
        self::assertNotSame('', $token);

        $client->request('PUT', '/api/v1/emergency-contacts', server: [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_ACCEPT' => 'application/json',
            'HTTP_AUTHORIZATION' => sprintf('Bearer %s', $token),
        ], content: json_encode([
            'contacts' => [
                [
                    'id' => 'contact-1',
                    'name' => 'Alice',
                    'phone' => '+33612345678',
                ],
            ],
        ], JSON_THROW_ON_ERROR));

        self::assertResponseIsSuccessful();
        $response = json_decode($client->getResponse()->getContent() ?: '', true, 512, JSON_THROW_ON_ERROR);

        self::assertIsArray($response);
        self::assertSame(1, $response['storedContacts'] ?? null);
    }
}
