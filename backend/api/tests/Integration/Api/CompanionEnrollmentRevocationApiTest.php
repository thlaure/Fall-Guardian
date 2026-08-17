<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use App\Domain\Device\Service\DeviceRegistrationService;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

final class CompanionEnrollmentRevocationApiTest extends WebTestCase
{
    public function testRevokingTheCreatingDeviceInvalidatesAnOutstandingEnrollmentToken(): void
    {
        $client = static::createClient();
        $protected = static::getContainer()->get(DeviceRegistrationService::class)->register('ios', '1.0.0');

        $client->request(
            Request::METHOD_POST,
            '/api/v1/companion-enrollments',
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
            content: '{"platform": "watchos"}',
        );
        self::assertResponseStatusCodeSame(Response::HTTP_CREATED);
        /** @var array{enrollmentToken: string} $enrollmentData */
        $enrollmentData = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);

        // The phone that created the enrollment is stolen and revoked before
        // the watch ever consumes the token.
        $client->request(
            Request::METHOD_POST,
            '/api/v1/devices/'.$protected->deviceId.'/revoke',
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
            content: '{}',
        );
        self::assertResponseStatusCodeSame(Response::HTTP_NO_CONTENT);

        $client->request(
            Request::METHOD_POST,
            '/api/v1/companion-enrollments/claim',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode([
                'enrollmentToken' => $enrollmentData['enrollmentToken'],
                'platform' => 'watchos',
                'appVersion' => '1.0.0',
            ], JSON_THROW_ON_ERROR),
        );

        self::assertResponseStatusCodeSame(Response::HTTP_NOT_FOUND);
    }
}
