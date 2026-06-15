<?php

declare(strict_types=1);

namespace App\Infrastructure\OpenApi;

use ApiPlatform\OpenApi\Factory\OpenApiFactoryInterface;
use ApiPlatform\OpenApi\Model\MediaType;
use ApiPlatform\OpenApi\Model\Operation;
use ApiPlatform\OpenApi\Model\PathItem;
use ApiPlatform\OpenApi\Model\Response;
use ApiPlatform\OpenApi\Model\Tag;
use ApiPlatform\OpenApi\OpenApi;

final readonly class FallGuardianOpenApiFactory implements OpenApiFactoryInterface
{
    public function __construct(private OpenApiFactoryInterface $decorated)
    {
    }

    /**
     * @param array<string, mixed> $context
     */
    public function __invoke(array $context = []): OpenApi
    {
        $openApi = ($this->decorated)($context);
        $openApi = $openApi
            ->withInfo($openApi->getInfo()->withDescription(
                'Device API for Fall Guardian alert delivery. Register once to obtain a device bearer token, then authenticate all fall-alert and caregiver-link calls with `Authorization: Bearer <token>`.',
            ))
            ->withTags([
                new Tag('Devices', 'Register an assisted-person or caregiver application installation.'),
                new Tag('Fall alerts', 'Report, cancel, and inspect fall-alert lifecycle state.'),
                new Tag('Caregiver links', 'Create and accept protected-person/caregiver relationships.'),
                new Tag('Caregiver alerts', 'Receive and acknowledge linked fall alerts.'),
            ]);

        $this->documentPost(
            $openApi,
            '/api/v1/devices/register',
            ['429' => 'Too many device registration requests from this client.'],
            example: ['platform' => 'ios', 'appVersion' => '1.0.0', 'deviceType' => 'protected_person'],
            requestDescription: 'Application installation and device role to register.',
            successDescriptions: [201 => 'Device registered. The response includes the bearer token to store securely.'],
        );
        $this->documentPost(
            $openApi,
            '/api/v1/fall-alerts',
            [
                '401' => 'Missing or invalid device bearer token.',
                '403' => 'A caregiver device cannot report a protected-person fall.',
                '429' => 'Too many fall alert submissions from this client.',
            ],
            example: [
                'clientAlertId' => '019e3005-a828-7db0-818f-1e57d20add1f',
                'fallTimestamp' => '2026-05-24T10:15:30+00:00',
                'locale' => 'en',
                'latitude' => 48.8566,
                'longitude' => 2.3522,
                'cancelled' => false,
            ],
            requestDescription: 'Detected fall event and optional location. Set `cancelled` to true when the protected person stopped the alert before caregiver notification; the fall is stored for caregiver history without urgent push dispatch.',
            successDescriptions: [201 => 'Fall alert accepted. Non-cancelled alerts are queued for caregiver delivery.'],
        );
        $this->documentPost($openApi, '/api/v1/fall-alerts/{clientAlertId}/cancel', [
            '401' => 'Missing or invalid device bearer token.',
            '403' => 'A caregiver device cannot cancel a protected-person fall.',
            '404' => 'No fall alert with that clientAlertId was found for the authenticated device.',
        ], successDescriptions: [201 => 'Fall alert cancelled.']);
        $this->documentGet($openApi, '/api/v1/fall-alerts/{id}', [
            '401' => 'Missing or invalid device bearer token.',
            '404' => 'No fall alert with that identifier was found for the authenticated device.',
        ], successDescriptions: [200 => 'Current fall-alert state.']);
        $this->documentPost($openApi, '/api/v1/invites', [
            '401' => 'Missing or invalid device bearer token.',
            '422' => 'Only a protected-person device can create an invitation.',
        ], successDescriptions: [201 => 'Caregiver invitation created.']);
        $this->documentPost($openApi, '/api/v1/invites/{code}/accept', [
            '401' => 'Missing or invalid device bearer token.',
            '404' => 'The invitation code was not found, expired, or was already used.',
            '422' => 'Only a caregiver device can accept an invitation.',
            '429' => 'Too many invitation acceptance requests from this client.',
        ], successDescriptions: [204 => 'Caregiver link created.']);
        $this->documentPost(
            $openApi,
            '/api/v1/caregiver/push-token',
            [
                '401' => 'Missing or invalid device bearer token.',
                '422' => 'Only a caregiver device can register a notification token.',
            ],
            example: ['fcmToken' => 'example-firebase-cloud-messaging-token'],
            requestDescription: 'Firebase Cloud Messaging registration token for this caregiver device.',
            successDescriptions: [204 => 'Notification token registered.'],
        );
        $this->documentGet($openApi, '/api/v1/caregiver/alerts', [
            '401' => 'Missing or invalid device bearer token.',
        ], successDescriptions: [200 => 'Fall alerts for linked protected persons.']);
        $this->documentPost($openApi, '/api/v1/fall-alerts/{id}/acknowledge', [
            '401' => 'Missing or invalid device bearer token.',
            '403' => 'The caregiver is not linked to the protected person for this alert.',
            '404' => 'No fall alert with that identifier was found.',
        ], successDescriptions: [204 => 'Alert acknowledgement recorded.']);

        return $openApi;
    }

    /**
     * @param array<int, string>        $errors
     * @param array<string, mixed>|null $example
     * @param array<int, string>        $successDescriptions
     */
    private function documentPost(
        OpenApi $openApi,
        string $path,
        array $errors,
        ?array $example = null,
        ?string $requestDescription = null,
        array $successDescriptions = [],
    ): void {
        $pathItem = $openApi->getPaths()->getPath($path);
        $operation = $pathItem?->getPost();

        if (!$pathItem instanceof PathItem || !$operation instanceof Operation) {
            return;
        }

        $operation = $this->withErrors($operation, $errors);
        $operation = $this->withResponseDescriptions($operation, $successDescriptions);

        if (null !== $example) {
            $operation = $this->withJsonRequestExample($operation, $example, $requestDescription);
        }

        $openApi->getPaths()->addPath($path, $pathItem->withPost($operation));
    }

    /**
     * @param array<int, string> $errors
     * @param array<int, string> $successDescriptions
     */
    private function documentGet(OpenApi $openApi, string $path, array $errors, array $successDescriptions = []): void
    {
        $pathItem = $openApi->getPaths()->getPath($path);
        $operation = $pathItem?->getGet();

        if (!$pathItem instanceof PathItem || !$operation instanceof Operation) {
            return;
        }

        $operation = $this->withErrors($operation, $errors);
        $operation = $this->withResponseDescriptions($operation, $successDescriptions);

        $openApi->getPaths()->addPath($path, $pathItem->withGet($operation));
    }

    /**
     * @param array<int, string> $errors
     */
    private function withErrors(Operation $operation, array $errors): Operation
    {
        foreach ($errors as $status => $description) {
            $operation = $operation->withResponse($status, new Response($description));
        }

        return $operation;
    }

    /**
     * @param array<int, string> $descriptions
     */
    private function withResponseDescriptions(Operation $operation, array $descriptions): Operation
    {
        foreach ($descriptions as $status => $description) {
            $response = $operation->getResponses()[(string) $status] ?? null;

            if ($response instanceof Response) {
                $operation = $operation->withResponse($status, $response->withDescription($description));
            }
        }

        return $operation;
    }

    /**
     * @param array<string, mixed> $example
     */
    private function withJsonRequestExample(Operation $operation, array $example, ?string $description): Operation
    {
        $requestBody = $operation->getRequestBody();
        $content = $requestBody?->getContent();

        if (null === $requestBody || null === $content) {
            return $operation;
        }

        if (null !== $description) {
            $requestBody = $requestBody->withDescription($description);
        }

        $content = clone $content;
        foreach (['application/json', 'application/ld+json'] as $contentType) {
            $mediaType = $content[$contentType] ?? null;

            if ($mediaType instanceof MediaType) {
                $content[$contentType] = $mediaType->withExample($example);
            }
        }

        return $operation->withRequestBody($requestBody->withContent($content));
    }
}
