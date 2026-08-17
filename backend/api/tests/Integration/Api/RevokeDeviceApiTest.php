<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use App\Domain\Device\Service\DeviceRegistrationService;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Uid\Uuid;

final class RevokeDeviceApiTest extends WebTestCase
{
    public function testAuthenticatedDeviceCanRevokeItselfAndCannotUseItsTokenAfterward(): void
    {
        $client = static::createClient();
        $registration = static::getContainer()->get(DeviceRegistrationService::class)->register('ios', '1.0.0');

        $client->request(
            Request::METHOD_POST,
            '/api/v1/devices/'.$registration->deviceId.'/revoke',
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$registration->deviceToken,
            ],
            content: '{}',
        );

        self::assertResponseStatusCodeSame(Response::HTTP_NO_CONTENT);

        $client->request(
            Request::METHOD_GET,
            '/api/v1/protected/linked-caregivers',
            server: ['HTTP_AUTHORIZATION' => 'Bearer '.$registration->deviceToken],
        );

        self::assertResponseStatusCodeSame(Response::HTTP_UNAUTHORIZED);
    }

    public function testRevokingAnUnknownDeviceReturns404(): void
    {
        $client = static::createClient();
        $registration = static::getContainer()->get(DeviceRegistrationService::class)->register('ios', '1.0.0');

        $client->request(
            Request::METHOD_POST,
            '/api/v1/devices/'.Uuid::v7()->toRfc4122().'/revoke',
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$registration->deviceToken,
            ],
            content: '{}',
        );

        self::assertResponseStatusCodeSame(Response::HTTP_NOT_FOUND);
    }

    public function testRevokingAnotherPersonsDeviceReturns403(): void
    {
        $client = static::createClient();
        $registrationService = static::getContainer()->get(DeviceRegistrationService::class);
        $requester = $registrationService->register('ios', '1.0.0');
        $otherPerson = $registrationService->register('ios', '1.0.0');

        $client->request(
            Request::METHOD_POST,
            '/api/v1/devices/'.$otherPerson->deviceId.'/revoke',
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$requester->deviceToken,
            ],
            content: '{}',
        );

        self::assertResponseStatusCodeSame(Response::HTTP_FORBIDDEN);

        $client->request(
            Request::METHOD_GET,
            '/api/v1/protected/linked-caregivers',
            server: ['HTTP_AUTHORIZATION' => 'Bearer '.$otherPerson->deviceToken],
        );

        self::assertResponseStatusCodeSame(Response::HTTP_OK);
    }
}
