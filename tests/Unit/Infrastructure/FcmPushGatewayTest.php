<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Infrastructure\Push\FcmPushGateway;

use const OPENSSL_KEYTYPE_RSA;

use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use RuntimeException;
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
        $fcmPayload = null;
        $oauthOptions = null;
        $fcmOptions = null;
        $oauthCalls = 0;
        $client = new MockHttpClient(static function (string $method, string $url, array $options) use (&$assertion, &$fcmPayload, &$oauthOptions, &$fcmOptions, &$oauthCalls): MockResponse {
            if ('https://oauth2.googleapis.com/token' === $url) {
                ++$oauthCalls;
                $oauthOptions = $options;
                parse_str((string) $options['body'], $body);
                $assertion = is_string($body['assertion'] ?? null) ? $body['assertion'] : null;

                return new MockResponse(json_encode(['access_token' => 'access-token', 'expires_in' => 3600]) ?: '{}');
            }

            $fcmOptions = $options;
            $decodedPayload = json_decode((string) $options['body'], true);
            $fcmPayload = is_array($decodedPayload) ? $decodedPayload : null;

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
        $gateway->send('fcm-token-2', 'alert-id-2', '2026-01-01T00:00:00+00:00', null, null);

        self::assertIsString($assertion);
        self::assertSame(1, $oauthCalls);
        self::assertSame(10.0, $oauthOptions['timeout'] ?? null);
        self::assertSame(10.0, $fcmOptions['timeout'] ?? null);
        $segments = explode('.', $assertion);
        self::assertCount(3, $segments);

        foreach ($segments as $segment) {
            self::assertDoesNotMatchRegularExpression('/[+=\/]/', $segment);
        }

        self::assertIsArray($fcmPayload);
        self::assertSame(
            'Fall detected',
            $fcmPayload['message']['notification']['title'] ?? null,
        );
        self::assertSame(
            'high',
            $fcmPayload['message']['android']['priority'] ?? null,
        );
        self::assertSame(
            'FLUTTER_NOTIFICATION_CLICK',
            $fcmPayload['message']['android']['notification']['click_action'] ?? null,
        );
    }

    #[Test]
    public function itSendsLinkRevokedNotificationWithCachedOauthToken(): void
    {
        $fcmPayload = null;
        $oauthCalls = 0;
        $client = new MockHttpClient(static function (string $method, string $url, array $options) use (&$fcmPayload, &$oauthCalls): MockResponse {
            if ('https://oauth2.googleapis.com/token' === $url) {
                ++$oauthCalls;

                return new MockResponse(json_encode(['access_token' => 'access-token', 'expires_in' => 3600]) ?: '{}');
            }

            $decodedPayload = json_decode((string) $options['body'], true);
            $fcmPayload = is_array($decodedPayload) ? $decodedPayload : null;
            $messageId = 'caregiver_revoked' === ($fcmPayload['message']['data']['type'] ?? null)
                ? 'revoked-id'
                : 'message-id';

            return new MockResponse(json_encode(['name' => 'projects/project-id/messages/'.$messageId]) ?: '{}');
        });

        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        $first = $gateway->send('fcm-token', 'alert-id', '2026-01-01T00:00:00+00:00', 48.8, 2.3);
        $second = $gateway->sendLinkRevoked('fcm-token');

        self::assertSame('projects/project-id/messages/message-id', $first['providerMessageId'] ?? null);
        self::assertSame('projects/project-id/messages/revoked-id', $second['providerMessageId'] ?? null);
        self::assertSame(1, $oauthCalls);
        self::assertIsArray($fcmPayload);
        self::assertSame('Caregiver link removed', $fcmPayload['message']['notification']['title'] ?? null);
        self::assertSame('caregiver_revoked', $fcmPayload['message']['data']['type'] ?? null);
        self::assertSame('default', $fcmPayload['message']['apns']['payload']['aps']['sound'] ?? null);
    }

    #[Test]
    public function itThrowsWhenServiceAccountJsonIsInvalid(): void
    {
        $gateway = new FcmPushGateway(new MockHttpClient(), 'project-id', '{invalid');

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('Invalid FCM service account JSON.');

        $gateway->send('fcm-token', 'alert-id', '2026-01-01T00:00:00+00:00', null, null);
    }

    #[Test]
    public function itThrowsWithoutLeakingFcmErrorBodyWhenSendFails(): void
    {
        $client = new MockHttpClient(static function (string $method, string $url): MockResponse {
            if ('https://oauth2.googleapis.com/token' === $url) {
                return new MockResponse(json_encode(['access_token' => 'access-token', 'expires_in' => 3600]) ?: '{}');
            }

            return new MockResponse('sensitive provider error', ['http_code' => 500]);
        });

        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('FCM send failed (HTTP 500).');

        $gateway->send('fcm-token', 'alert-id', '2026-01-01T00:00:00+00:00', null, null);
    }

    private function serviceAccountJson(): string
    {
        $privateKey = openssl_pkey_new([
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
        ]);
        self::assertNotFalse($privateKey);

        $privateKeyPem = '';
        openssl_pkey_export($privateKey, $privateKeyPem);

        return json_encode([
            'client_email' => 'firebase-adminsdk@example.iam.gserviceaccount.com',
            'private_key' => $privateKeyPem,
        ]) ?: '{}';
    }
}
