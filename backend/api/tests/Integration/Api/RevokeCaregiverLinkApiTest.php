<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use App\Domain\Device\Service\DeviceRegistrationService;
use App\Enum\DeviceType;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Uid\Uuid;

final class RevokeCaregiverLinkApiTest extends WebTestCase
{
    public function testProtectedPersonCanRevokeALinkedCaregiver(): void
    {
        $client = static::createClient();
        $registrationService = static::getContainer()->get(DeviceRegistrationService::class);
        $protected = $registrationService->register('ios', '1.0.0');
        $caregiver = $registrationService->register('android', '1.0.0', DeviceType::Caregiver);

        $client->request(
            Request::METHOD_POST,
            '/api/v1/invites',
            server: ['HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken],
        );
        self::assertResponseStatusCodeSame(Response::HTTP_CREATED);
        /** @var array{code: string} $inviteData */
        $inviteData = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);

        $client->request(
            Request::METHOD_POST,
            sprintf('/api/v1/invites/%s/accept', $inviteData['code']),
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$caregiver->deviceToken,
            ],
            content: '{}',
        );
        self::assertResponseStatusCodeSame(Response::HTTP_NO_CONTENT);

        $client->request(
            Request::METHOD_GET,
            '/api/v1/protected/linked-caregivers',
            server: [
                'HTTP_ACCEPT' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
        );
        self::assertResponseStatusCodeSame(Response::HTTP_OK);
        /** @var list<array{id: string}> $links */
        $links = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        self::assertCount(1, $links);
        $linkId = $links[0]['id'];

        // Revoking is idempotent to try twice: the second attempt must find
        // nothing left to revoke.
        $client->request(
            Request::METHOD_POST,
            sprintf('/api/v1/protected/linked-caregivers/%s/revoke', $linkId),
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
            content: '{}',
        );
        self::assertResponseStatusCodeSame(Response::HTTP_NO_CONTENT);

        $client->request(
            Request::METHOD_GET,
            '/api/v1/protected/linked-caregivers',
            server: [
                'HTTP_ACCEPT' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
        );
        self::assertResponseStatusCodeSame(Response::HTTP_OK);
        $linksAfterRevoke = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        self::assertSame([], $linksAfterRevoke);

        $client->request(
            Request::METHOD_POST,
            sprintf('/api/v1/protected/linked-caregivers/%s/revoke', $linkId),
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
            content: '{}',
        );
        self::assertResponseStatusCodeSame(Response::HTTP_NOT_FOUND);
    }

    public function testRevokingAnUnknownLinkReturns404(): void
    {
        $client = static::createClient();
        $protected = static::getContainer()->get(DeviceRegistrationService::class)->register('ios', '1.0.0');

        $client->request(
            Request::METHOD_POST,
            sprintf('/api/v1/protected/linked-caregivers/%s/revoke', Uuid::v7()->toRfc4122()),
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
            content: '{}',
        );

        self::assertResponseStatusCodeSame(Response::HTTP_NOT_FOUND);
    }

    public function testAProtectedPersonCannotRevokeAnotherPersonsCaregiverLink(): void
    {
        $client = static::createClient();
        $registrationService = static::getContainer()->get(DeviceRegistrationService::class);
        $protected = $registrationService->register('ios', '1.0.0');
        $caregiver = $registrationService->register('android', '1.0.0', DeviceType::Caregiver);
        $otherProtected = $registrationService->register('ios', '1.0.0');

        $client->request(
            Request::METHOD_POST,
            '/api/v1/invites',
            server: ['HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken],
        );
        self::assertResponseStatusCodeSame(Response::HTTP_CREATED);
        /** @var array{code: string} $inviteData */
        $inviteData = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);

        $client->request(
            Request::METHOD_POST,
            sprintf('/api/v1/invites/%s/accept', $inviteData['code']),
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$caregiver->deviceToken,
            ],
            content: '{}',
        );
        self::assertResponseStatusCodeSame(Response::HTTP_NO_CONTENT);

        $client->request(
            Request::METHOD_GET,
            '/api/v1/protected/linked-caregivers',
            server: [
                'HTTP_ACCEPT' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
        );
        /** @var list<array{id: string}> $links */
        $links = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        $linkId = $links[0]['id'];

        $client->request(
            Request::METHOD_POST,
            sprintf('/api/v1/protected/linked-caregivers/%s/revoke', $linkId),
            server: [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$otherProtected->deviceToken,
            ],
            content: '{}',
        );

        self::assertResponseStatusCodeSame(Response::HTTP_NOT_FOUND);

        $client->request(
            Request::METHOD_GET,
            '/api/v1/protected/linked-caregivers',
            server: [
                'HTTP_ACCEPT' => 'application/json',
                'HTTP_AUTHORIZATION' => 'Bearer '.$protected->deviceToken,
            ],
        );
        $linksStillActive = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        self::assertCount(1, $linksStillActive);
    }
}
