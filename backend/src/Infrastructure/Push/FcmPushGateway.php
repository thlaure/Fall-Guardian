<?php

declare(strict_types=1);

namespace App\Infrastructure\Push;

use App\Domain\Push\Port\PushGatewayInterface;

use function base64_encode;
use function is_array;
use function is_string;
use function json_decode;
use function json_encode;
use function openssl_pkey_get_private;
use function openssl_sign;

use RuntimeException;

use function sprintf;

use Symfony\Contracts\HttpClient\HttpClientInterface;

use function time;

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
                'data' => $data,
                'android' => [
                    'priority' => 'high',
                ],
                'apns' => [
                    'headers' => [
                        'apns-priority' => '10',
                    ],
                ],
            ],
        ];

        $response = $this->httpClient->request(
            'POST',
            sprintf(self::FCM_SEND_URL, $this->projectId),
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $accessToken,
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
            throw new RuntimeException(sprintf(
                'FCM send failed (HTTP %d): %s',
                $statusCode,
                $responseBody,
            ));
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

        $signingInput = base64_encode($headerJson) . '.' . base64_encode($claimsJson);
        $privateKey = openssl_pkey_get_private($privateKeyPem);

        if (false === $privateKey) {
            throw new RuntimeException('Failed to load FCM private key.');
        }

        openssl_sign($signingInput, $signature, $privateKey, 'SHA256');
        $jwt = $signingInput . '.' . base64_encode((string) $signature);

        $response = $this->httpClient->request('POST', self::OAUTH_TOKEN_URL, [
            'body' => 'grant_type=' . rawurlencode('urn:ietf:params:oauth:grant-type:jwt-bearer') . '&assertion=' . rawurlencode($jwt),
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
}
