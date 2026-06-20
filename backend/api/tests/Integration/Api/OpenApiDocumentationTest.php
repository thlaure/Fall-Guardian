<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use const JSON_THROW_ON_ERROR;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Request;

final class OpenApiDocumentationTest extends WebTestCase
{
    public function testDocumentationExplainsAuthenticationAndAlertLifecycle(): void
    {
        $client = self::createClient();
        $client->request(Request::METHOD_GET, '/docs.jsonopenapi');

        self::assertResponseIsSuccessful();

        /** @var array<string, mixed> $documentation */
        $documentation = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);

        self::assertSame('bearer', $documentation['components']['securitySchemes']['deviceBearer']['scheme']);
        self::assertSame([], $documentation['paths']['/api/v1/devices/register']['post']['security'] ?? []);
        self::assertSame(
            [['deviceBearer' => []]],
            $documentation['paths']['/api/v1/fall-alerts']['post']['security'],
        );
        self::assertArrayHasKey('429', $documentation['paths']['/api/v1/fall-alerts']['post']['responses']);
        self::assertSame(
            48.8566,
            $documentation['paths']['/api/v1/fall-alerts']['post']['requestBody']['content']['application/json']['example']['latitude'],
        );
        self::assertFalse(
            $documentation['paths']['/api/v1/fall-alerts']['post']['requestBody']['content']['application/json']['example']['cancelled'],
        );
        self::assertSame(
            'Detected fall event and optional location. Set `cancelled` to true when the protected person stopped the alert before caregiver notification; the fall is stored for caregiver history without urgent push dispatch.',
            $documentation['paths']['/api/v1/fall-alerts']['post']['requestBody']['description'],
        );
        self::assertSame(
            'Fall alert accepted. Non-cancelled alerts are queued for caregiver delivery.',
            $documentation['paths']['/api/v1/fall-alerts']['post']['responses']['201']['description'],
        );
        self::assertArrayNotHasKey(
            'requestBody',
            $documentation['paths']['/api/v1/fall-alerts/{clientAlertId}/cancel']['post'],
        );
        self::assertArrayNotHasKey(
            '429',
            $documentation['paths']['/api/v1/fall-alerts/{id}/acknowledge']['post']['responses'],
        );
    }
}
