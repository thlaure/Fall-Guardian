<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\PermanentPushDeliveryException;
use App\Domain\Push\Exception\PushDeliveryException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Domain\Push\Port\PushGatewayInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Contracts\HttpClient\Exception\ExceptionInterface as HttpClientExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

final class FcmPushGateway implements PushGatewayInterface
{
    private const string FCM_SEND_URL = 'https://fcm.googleapis.com/v1/projects/%s/messages:send';

    private const string OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private const string OAUTH_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    private const int TOKEN_EXPIRY_SAFETY_SECONDS = 60;

    private const float HTTP_TIMEOUT_SECONDS = 10.0;

    /** Hard upper bound for one HTTP exchange, so a dispatch round stays well below the stale-claim threshold. */
    public const float HTTP_MAX_DURATION_SECONDS = 15.0;

    /**
     * HTTP statuses after which the same request may succeed later.
     * 401 is included because an expired OAuth access token is refreshed.
     */
    private const array TRANSIENT_HTTP_STATUSES = [401, 408, 429, 500, 502, 503, 504];

    /** BadRequest field violation that singles out the registration token. */
    private const string TOKEN_FIELD = 'message.token';

    private ?string $cachedAccessToken = null;

    private int $cachedAccessTokenExpiresAt = 0;

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly string $projectId,
        private readonly string $serviceAccountJson,
    ) {
    }

    public function getProviderName(): string
    {
        return 'fcm';
    }

    public function send(string $fcmToken, FallAlertPushPayload $payload): array
    {
        return $this->postMessage(
            $fcmToken,
            $payload->reminder ? 'Fall alert still unacknowledged' : 'Fall detected',
            'Tap to view and acknowledge the alert.',
            $payload->toData(),
        );
    }

    public function sendLinkRevoked(string $fcmToken): array
    {
        return $this->postMessage(
            $fcmToken,
            'Caregiver link removed',
            'You have been removed as a caregiver.',
            ['type' => 'caregiver_revoked'],
        );
    }

    /**
     * @param array<string, string> $data
     *
     * @return array{providerMessageId: ?string, status: string}
     */
    private function postMessage(string $fcmToken, string $title, string $body, array $data): array
    {
        $accessToken = $this->getAccessToken();

        $payload = [
            'message' => [
                'token' => $fcmToken,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $data,
                'android' => [
                    'priority' => 'high',
                    'notification' => [
                        'channel_id' => 'fall_alerts',
                        'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                    ],
                ],
                'apns' => [
                    'headers' => [
                        'apns-priority' => '10',
                    ],
                    'payload' => [
                        'aps' => [
                            'alert' => [
                                'title' => $title,
                                'body' => $body,
                            ],
                            'sound' => 'default',
                        ],
                    ],
                ],
            ],
        ];

        try {
            $response = $this->httpClient->request(
                Request::METHOD_POST,
                sprintf(self::FCM_SEND_URL, $this->projectId),
                [
                    'headers' => [
                        'Authorization' => 'Bearer '.$accessToken,
                        'Content-Type' => 'application/json',
                    ],
                    'body' => json_encode($payload),
                    'timeout' => self::HTTP_TIMEOUT_SECONDS,
                    'max_duration' => self::HTTP_MAX_DURATION_SECONDS,
                ],
            );

            $statusCode = $response->getStatusCode();
            $responseBody = $response->getContent(false);
        } catch (HttpClientExceptionInterface $exception) {
            throw new TransientPushDeliveryException('FCM send failed (transport error).', 'transport', $exception);
        }

        /** @var array<string, mixed>|null $responseData */
        $responseData = json_decode($responseBody, true);

        if ($statusCode < 200 || $statusCode >= 300) {
            throw $this->classifyFailure($statusCode, is_array($responseData) ? $responseData : null);
        }

        $providerMessageId = is_array($responseData) && isset($responseData['name']) && is_string($responseData['name'])
            ? $responseData['name']
            : null;

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }

    /**
     * Maps an FCM error response to a typed exception. Only the HTTP status and
     * the FCM error code are kept: the provider message body is never exposed.
     *
     * A token is only reported dead when FCM says so unambiguously: the
     * UNREGISTERED error code, or INVALID_ARGUMENT whose field violation
     * targets `message.token`. INVALID_ARGUMENT is also returned for malformed
     * messages, and SENDER_ID_MISMATCH or a bare 404 can come from our own
     * misconfiguration; treating those as dead tokens would wipe every
     * caregiver's token, so they are permanent failures that keep the token.
     *
     * @see https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
     *
     * @param array<string, mixed>|null $responseData
     */
    private function classifyFailure(int $statusCode, ?array $responseData): PushDeliveryException
    {
        $errorCode = self::extractFcmErrorCode($responseData);
        $reason = $errorCode ?? sprintf('http_%d', $statusCode);
        $message = sprintf('FCM send failed (HTTP %d).', $statusCode);

        if ('UNREGISTERED' === $errorCode
            || ('INVALID_ARGUMENT' === $errorCode && self::hasTokenFieldViolation($responseData))) {
            return new InvalidPushTokenException($message, $reason);
        }

        if (in_array($statusCode, self::TRANSIENT_HTTP_STATUSES, true)
            || in_array($errorCode, ['UNAVAILABLE', 'INTERNAL', 'QUOTA_EXCEEDED'], true)) {
            return new TransientPushDeliveryException($message, $reason);
        }

        return new PermanentPushDeliveryException($message, $reason);
    }

    /** @param array<string, mixed>|null $responseData */
    private static function hasTokenFieldViolation(?array $responseData): bool
    {
        $error = $responseData['error'] ?? null;
        $details = is_array($error) ? ($error['details'] ?? null) : null;

        if (!is_array($details)) {
            return false;
        }

        foreach ($details as $detail) {
            $violations = is_array($detail) ? ($detail['fieldViolations'] ?? null) : null;

            if (!is_array($violations)) {
                continue;
            }

            foreach ($violations as $violation) {
                if (is_array($violation) && self::TOKEN_FIELD === ($violation['field'] ?? null)) {
                    return true;
                }
            }
        }

        return false;
    }

    /** @param array<string, mixed>|null $responseData */
    private static function extractFcmErrorCode(?array $responseData): ?string
    {
        $error = $responseData['error'] ?? null;

        if (!is_array($error)) {
            return null;
        }

        $details = $error['details'] ?? null;

        if (is_array($details)) {
            foreach ($details as $detail) {
                if (is_array($detail) && isset($detail['errorCode']) && is_string($detail['errorCode'])) {
                    return $detail['errorCode'];
                }
            }
        }

        return isset($error['status']) && is_string($error['status']) ? $error['status'] : null;
    }

    private function getAccessToken(): string
    {
        try {
            return $this->fetchAccessToken();
        } catch (PushDeliveryException $exception) {
            throw $exception;
        } catch (HttpClientExceptionInterface $exception) {
            throw new TransientPushDeliveryException('Failed to obtain FCM access token.', 'oauth', $exception);
        }
    }

    private function fetchAccessToken(): string
    {
        $now = time();

        if (null !== $this->cachedAccessToken && $this->cachedAccessTokenExpiresAt > $now + self::TOKEN_EXPIRY_SAFETY_SECONDS) {
            return $this->cachedAccessToken;
        }

        /** @var array<string, mixed>|null $serviceAccount */
        $serviceAccount = json_decode($this->serviceAccountJson, true);

        if (!is_array($serviceAccount)) {
            throw new TransientPushDeliveryException('Invalid FCM service account JSON.', 'configuration');
        }

        $clientEmail = is_string($serviceAccount['client_email'] ?? null) ? $serviceAccount['client_email'] : '';
        $privateKeyPem = is_string($serviceAccount['private_key'] ?? null) ? $serviceAccount['private_key'] : '';

        $headerJson = json_encode(['alg' => 'RS256', 'typ' => 'JWT']);
        $claimsJson = json_encode([
            'iss' => $clientEmail,
            'scope' => self::OAUTH_SCOPE,
            'aud' => self::OAUTH_TOKEN_URL,
            'iat' => $now,
            'exp' => $now + 3600,
        ]);

        if (false === $headerJson || false === $claimsJson) {
            throw new TransientPushDeliveryException('Failed to encode JWT header or claims.', 'configuration');
        }

        $signingInput = self::base64UrlEncode($headerJson).'.'.self::base64UrlEncode($claimsJson);
        $privateKey = openssl_pkey_get_private($privateKeyPem);

        if (false === $privateKey) {
            throw new TransientPushDeliveryException('Failed to load FCM private key.', 'configuration');
        }

        if (!openssl_sign($signingInput, $signature, $privateKey, 'SHA256')) {
            throw new TransientPushDeliveryException('Failed to sign FCM JWT.', 'configuration');
        }

        $jwt = $signingInput.'.'.self::base64UrlEncode((string) $signature);

        $response = $this->httpClient->request(Request::METHOD_POST, self::OAUTH_TOKEN_URL, [
            'body' => 'grant_type='.rawurlencode('urn:ietf:params:oauth:grant-type:jwt-bearer').'&assertion='.rawurlencode($jwt),
            'headers' => [
                'Content-Type' => 'application/x-www-form-urlencoded',
            ],
            'timeout' => self::HTTP_TIMEOUT_SECONDS,
            'max_duration' => self::HTTP_MAX_DURATION_SECONDS,
        ]);

        /** @var array<string, mixed>|null $tokenData */
        $tokenData = json_decode($response->getContent(), true);

        if (!is_array($tokenData) || !isset($tokenData['access_token']) || !is_string($tokenData['access_token'])) {
            throw new TransientPushDeliveryException('Failed to obtain FCM access token.', 'oauth');
        }

        $expiresIn = isset($tokenData['expires_in']) && is_int($tokenData['expires_in']) ? $tokenData['expires_in'] : 3600;
        $this->cachedAccessToken = $tokenData['access_token'];
        $this->cachedAccessTokenExpiresAt = $now + $expiresIn;

        return $this->cachedAccessToken;
    }

    private static function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
