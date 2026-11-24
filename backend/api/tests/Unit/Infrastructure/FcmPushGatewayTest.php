<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\PermanentPushDeliveryException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Infrastructure\Push\FcmPushGateway;

use const OPENSSL_KEYTYPE_RSA;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use RuntimeException;
use Symfony\Component\HttpClient\Exception\TransportException;
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

        $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:30+00:00', null, null));
        $gateway->send('fcm-token-2', new FallAlertPushPayload('alert-id-2', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:30+00:00', null, null));

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

        $first = $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:30+00:00', 48.8, 2.3));
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

        $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:30+00:00', null, null));
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

        $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:30+00:00', null, null));
    }

    #[Test]
    public function itKeepsExistingDataKeysAndAddsTheCaregiverContractKeys(): void
    {
        $fcmPayload = null;
        $client = $this->clientCapturingSend($fcmPayload, new MockResponse(json_encode(['name' => 'message-id']) ?: '{}'));
        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:30Z', 48.8, 2.3, 'Mamie', false));

        self::assertIsArray($fcmPayload);
        self::assertSame([
            'type' => 'fall_alert',
            'alertId' => 'alert-id',
            'fallTimestamp' => '2026-01-01T00:00:00Z',
            'cancelDeadlineAt' => '2026-01-01T00:00:30Z',
            'reminder' => '0',
            'latitude' => '48.8',
            'longitude' => '2.3',
            'protectedPersonName' => 'Mamie',
        ], $fcmPayload['message']['data'] ?? null);
        self::assertSame(15.0, $this->lastOptions['max_duration'] ?? null);
    }

    #[Test]
    public function itMarksRemindersAndOmitsMissingOptionalKeys(): void
    {
        $fcmPayload = null;
        $client = $this->clientCapturingSend($fcmPayload, new MockResponse(json_encode(['name' => 'message-id']) ?: '{}'));
        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:30Z', reminder: true));

        self::assertIsArray($fcmPayload);
        $data = $fcmPayload['message']['data'] ?? [];
        self::assertSame('1', $data['reminder'] ?? null);
        self::assertArrayNotHasKey('protectedPersonName', $data);
        self::assertArrayNotHasKey('latitude', $data);
        self::assertSame('Fall alert still unacknowledged', $fcmPayload['message']['notification']['title'] ?? null);
    }

    /** @return iterable<string, array{int, array<string, mixed>|null, class-string, string}> */
    public static function failureResponses(): iterable
    {
        // Only an unambiguous "this token is dead" deletes the token.
        yield 'unregistered token' => [404, self::fcmError(404, 'NOT_FOUND', 'UNREGISTERED'), InvalidPushTokenException::class, 'UNREGISTERED'];
        yield 'invalid argument on message.token' => [400, self::fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'message.token'), InvalidPushTokenException::class, 'INVALID_ARGUMENT'];
        // Rejected message (e.g. payload regression): permanent for this attempt, token kept.
        yield 'invalid argument on the payload' => [400, self::fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'message.android.notification'), PermanentPushDeliveryException::class, 'INVALID_ARGUMENT'];
        yield 'invalid argument without field violation' => [400, self::fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT'), PermanentPushDeliveryException::class, 'INVALID_ARGUMENT'];
        yield 'sender id mismatch (possible misconfiguration)' => [403, self::fcmError(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH'), PermanentPushDeliveryException::class, 'SENDER_ID_MISMATCH'];
        yield 'bare 404 without body' => [404, null, PermanentPushDeliveryException::class, 'http_404'];
        // Transient: retried later, token kept.
        yield 'quota exceeded' => [429, self::fcmError(429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'), TransientPushDeliveryException::class, 'QUOTA_EXCEEDED'];
        yield 'fcm unavailable' => [503, self::fcmError(503, 'UNAVAILABLE', 'UNAVAILABLE'), TransientPushDeliveryException::class, 'UNAVAILABLE'];
        yield 'internal error without body' => [500, null, TransientPushDeliveryException::class, 'http_500'];
        yield 'expired access token' => [401, ['error' => ['status' => 'UNAUTHENTICATED']], TransientPushDeliveryException::class, 'UNAUTHENTICATED'];
    }

    /**
     * @param array<string, mixed>|null $body
     * @param class-string              $expectedClass
     */
    #[Test]
    #[DataProvider('failureResponses')]
    public function itClassifiesProviderFailuresAsPermanentTokenOrTransient(int $status, ?array $body, string $expectedClass, string $expectedReason): void
    {
        $fcmPayload = null;
        $client = $this->clientCapturingSend(
            $fcmPayload,
            new MockResponse(null === $body ? 'token fcm-secret-token rejected' : (json_encode($body) ?: '{}'), ['http_code' => $status]),
        );
        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        try {
            $gateway->send('fcm-secret-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:30Z'));
            self::fail('Expected a push delivery exception.');
        } catch (InvalidPushTokenException|PermanentPushDeliveryException|TransientPushDeliveryException $exception) {
            self::assertInstanceOf($expectedClass, $exception);
            self::assertSame($expectedReason, $exception->getReason());
            self::assertSame(sprintf('FCM send failed (HTTP %d).', $status), $exception->getMessage());
            self::assertStringNotContainsString('fcm-secret-token', $exception->getMessage());
        }
    }

    #[Test]
    public function itTreatsTransportErrorsAsTransient(): void
    {
        $client = new MockHttpClient(static function (string $method, string $url): MockResponse {
            if ('https://oauth2.googleapis.com/token' === $url) {
                return new MockResponse(json_encode(['access_token' => 'access-token', 'expires_in' => 3600]) ?: '{}');
            }

            throw new TransportException('Connection timed out');
        });
        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        try {
            $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:30Z'));
            self::fail('Expected a transient exception.');
        } catch (TransientPushDeliveryException $exception) {
            self::assertSame('transport', $exception->getReason());
        }
    }

    #[Test]
    public function itTreatsAccessTokenFetchFailureAsTransient(): void
    {
        $client = new MockHttpClient(new MockResponse('{"error":"backend"}', ['http_code' => 503]));
        $gateway = new FcmPushGateway($client, 'project-id', $this->serviceAccountJson());

        try {
            $gateway->send('fcm-token', new FallAlertPushPayload('alert-id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:30Z'));
            self::fail('Expected a transient exception.');
        } catch (TransientPushDeliveryException $exception) {
            self::assertSame('oauth', $exception->getReason());
        }
    }

    /** @var array<string, mixed> */
    private array $lastOptions = [];

    /** @param-out array<string, mixed>|null $fcmPayload */
    private function clientCapturingSend(?array &$fcmPayload, MockResponse $sendResponse): MockHttpClient
    {
        return new MockHttpClient(function (string $method, string $url, array $options) use (&$fcmPayload, $sendResponse): MockResponse {
            if ('https://oauth2.googleapis.com/token' === $url) {
                return new MockResponse(json_encode(['access_token' => 'access-token', 'expires_in' => 3600]) ?: '{}');
            }

            $this->lastOptions = $options;
            $decoded = json_decode((string) $options['body'], true);
            $fcmPayload = is_array($decoded) ? $decoded : null;

            return $sendResponse;
        });
    }

    /** @return array<string, mixed> */
    private static function fcmError(int $code, string $status, string $errorCode, ?string $violatedField = null): array
    {
        $details = [['@type' => 'type.googleapis.com/google.firebase.fcm.v1.FcmError', 'errorCode' => $errorCode]];

        if (null !== $violatedField) {
            $details[] = [
                '@type' => 'type.googleapis.com/google.rpc.BadRequest',
                'fieldViolations' => [['field' => $violatedField, 'description' => 'Invalid value']],
            ];
        }

        return ['error' => [
            'code' => $code,
            'message' => 'Request contains an invalid argument.',
            'status' => $status,
            'details' => $details,
        ]];
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
