<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Infrastructure\Push\FcmPushGateway;

use const OPENSSL_KEYTYPE_RSA;

use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpClient\MockHttpClient;
use Symfony\Component\HttpClient\Response\MockResponse;

final class FcmPushGatewayTest extends TestCase
{
    #[Test]
    public function itUsesBase64UrlEncodedJwtForOauthAssertion(): void
    {
        $privateKey = openssl_pkey_new([
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
        ]);
        self::assertNotFalse($privateKey);

        $privateKeyPem = '';
        openssl_pkey_export($privateKey, $privateKeyPem);

        $assertion = null;
        $client = new MockHttpClient(static function (string $method, string $url, array $options) use (&$assertion): MockResponse {
            if ('https://oauth2.googleapis.com/token' === $url) {
                parse_str((string) $options['body'], $body);
                $assertion = is_string($body['assertion'] ?? null) ? $body['assertion'] : null;

                return new MockResponse(json_encode(['access_token' => 'access-token']) ?: '{}');
            }

            return new MockResponse(json_encode(['name' => 'projects/project-id/messages/message-id']) ?: '{}');
        });

        $gateway = new FcmPushGateway(
            $client,
            'project-id',
            json_encode([
                'client_email' => 'firebase-adminsdk@example.iam.gserviceaccount.com',
                'private_key' => $privateKeyPem,
            ]) ?: '{}',
        );

        $gateway->send('fcm-token', 'alert-id', '2026-01-01T00:00:00+00:00', null, null);

        self::assertIsString($assertion);
        $segments = explode('.', $assertion);
        self::assertCount(3, $segments);

        foreach ($segments as $segment) {
            self::assertDoesNotMatchRegularExpression('/[+=\/]/', $segment);
        }
    }
}
