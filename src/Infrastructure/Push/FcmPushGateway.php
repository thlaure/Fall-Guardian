<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Port\PushGatewayInterface;
use RuntimeException;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Contracts\HttpClient\HttpClientInterface;

final readonly class FcmPushGateway implements PushGatewayInterface
{
    private const string FCM_SEND_URL = 'https://fcm.googleapis.com/v1/projects/%s/messages:send';

    private const string OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private const string OAUTH_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    public function __construct(
        private HttpClientInterface $httpClient,
        private string $projectId,
        private string $serviceAccountJson,
    ) {
    }

    public function getProviderName(): string
    {
        return 'fcm';
    }

    public function send(string $fcmToken, string $alertId, string $fallTimestamp, ?float $latitude, ?float $longitude): array
    {
        $accessToken = $this->getAccessToken();

        $data = [
            'alertId' => $alertId,
            'fallTimestamp' => $fallTimestamp,
        ];

        if (null !== $latitude) {
            $data['latitude'] = (string) $latitude;
        }

        if (null !== $longitude) {
            $data['longitude'] = (string) $longitude;
        }

        $payload = [
            'message' => [
                'token' => $fcmToken,
                'notification' => [
                    'title' => 'Fall detected',
                    'body' => 'Tap to view and acknowledge the alert.',
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
                                'title' => 'Fall detected',
                                'body' => 'Tap to view and acknowledge the alert.',
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
            ],
        );

        $statusCode = $response->getStatusCode();
        $responseBody = $response->getContent(false);
        /** @var array<string, mixed>|null $body */
        $body = json_decode($responseBody, true);

        if ($statusCode < 200 || $statusCode >= 300) {
            throw new RuntimeException(sprintf('FCM send failed (HTTP %d): %s', $statusCode, $responseBody));
        }

        $providerMessageId = is_array($body) && isset($body['name']) && is_string($body['name'])
            ? $body['name']
            : null;

        return [
            'providerMessageId' => $providerMessageId,
            'status' => 'sent',
        ];
    }

    private function getAccessToken(): string
    {
        /** @var array<string, mixed>|null $serviceAccount */
        $serviceAccount = json_decode($this->serviceAccountJson, true);

        if (!is_array($serviceAccount)) {
            throw new RuntimeException('Invalid FCM service account JSON.');
        }

        $clientEmail = is_string($serviceAccount['client_email'] ?? null) ? $serviceAccount['client_email'] : '';
        $privateKeyPem = is_string($serviceAccount['private_key'] ?? null) ? $serviceAccount['private_key'] : '';

        $now = time();
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
        ]);

        /** @var array<string, mixed>|null $tokenData */
        $tokenData = json_decode($response->getContent(), true);

        if (!is_array($tokenData) || !isset($tokenData['access_token']) || !is_string($tokenData['access_token'])) {
            throw new RuntimeException('Failed to obtain FCM access token.');
        }

        return $tokenData['access_token'];
    }

    private static function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
