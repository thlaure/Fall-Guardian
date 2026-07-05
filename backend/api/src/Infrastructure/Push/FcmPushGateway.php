<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Port\PushGatewayInterface;
use RuntimeException;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Contracts\HttpClient\HttpClientInterface;

final class FcmPushGateway implements PushGatewayInterface
{
    private const string FCM_SEND_URL = 'https://fcm.googleapis.com/v1/projects/%s/messages:send';

    private const string OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private const string OAUTH_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    private const int TOKEN_EXPIRY_SAFETY_SECONDS = 60;

    private const float HTTP_TIMEOUT_SECONDS = 10.0;

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

    public function send(string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): array
    {
        $data = [
            'type' => 'fall_alert',
            'alertId' => $alertId,
            'fallTimestamp' => $fallTimestamp,
        ];

        if (null !== $latitude) {
            $data['latitude'] = (string) $latitude;
        }

        if (null !== $longitude) {
            $data['longitude'] = (string) $longitude;
        }

        return $this->postMessage($fcmToken, 'Fall detected', 'Tap to view and acknowledge the alert.', $data);
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
            ],
        );

        $statusCode = $response->getStatusCode();
        $responseBody = $response->getContent(false);
        /** @var array<string, mixed>|null $responseData */
        $responseData = json_decode($responseBody, true);

        if ($statusCode < 200 || $statusCode >= 300) {
            throw new RuntimeException(sprintf('FCM send failed (HTTP %d).', $statusCode));
        }

        $providerMessageId = is_array($responseData) && isset($responseData['name']) && is_string($responseData['name'])
            ? $responseData['name']
            : null;

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }

    private function getAccessToken(): string
    {
        $now = time();

        if (null !== $this->cachedAccessToken && $this->cachedAccessTokenExpiresAt > $now + self::TOKEN_EXPIRY_SAFETY_SECONDS) {
            return $this->cachedAccessToken;
        }

        /** @var array<string, mixed>|null $serviceAccount */
        $serviceAccount = json_decode($this->serviceAccountJson, true);

        if (!is_array($serviceAccount)) {
            throw new RuntimeException('Invalid FCM service account JSON.');
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
            throw new RuntimeException('Failed to encode JWT header or claims.');
        }

        $signingInput = self::base64UrlEncode($headerJson).'.'.self::base64UrlEncode($claimsJson);
        $privateKey = openssl_pkey_get_private($privateKeyPem);

        if (false === $privateKey) {
            throw new RuntimeException('Failed to load FCM private key.');
        }

        if (!openssl_sign($signingInput, $signature, $privateKey, 'SHA256')) {
            throw new RuntimeException('Failed to sign FCM JWT.');
        }

        $jwt = $signingInput.'.'.self::base64UrlEncode((string) $signature);

        $response = $this->httpClient->request(Request::METHOD_POST, self::OAUTH_TOKEN_URL, [
            'body' => 'grant_type='.rawurlencode('urn:ietf:params:oauth:grant-type:jwt-bearer').'&assertion='.rawurlencode($jwt),
            'headers' => [
                'Content-Type' => 'application/x-www-form-urlencoded',
            ],
            'timeout' => self::HTTP_TIMEOUT_SECONDS,
        ]);

        /** @var array<string, mixed>|null $tokenData */
        $tokenData = json_decode($response->getContent(), true);

        if (!is_array($tokenData) || !isset($tokenData['access_token']) || !is_string($tokenData['access_token'])) {
            throw new RuntimeException('Failed to obtain FCM access token.');
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
