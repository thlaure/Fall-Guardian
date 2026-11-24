<?php

declare(strict_types=1);

namespace App\Tests\Integration\Api;

use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use Doctrine\DBAL\Connection;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Request;

final class HealthControllerTest extends WebTestCase
{
    public function testLivenessResponseIsUnchanged(): void
    {
        $client = self::createClient();
        $client->request(Request::METHOD_GET, '/health');

        self::assertResponseIsSuccessful();
        self::assertSame(
            ['status' => 'ok', 'service' => 'fall-guardian-backend'],
            json_decode((string) $client->getResponse()->getContent(), true),
        );
    }

    public function testReadinessIsOkWithALiveReconcilerAndNoBacklog(): void
    {
        $client = self::createClient();
        $client->disableReboot();
        $connection = self::getContainer()->get(Connection::class);
        self::assertInstanceOf(Connection::class, $connection);

        $connection->beginTransaction();

        try {
            // Isolate from rows left by other tests: nothing is due.
            $connection->executeStatement("UPDATE fall_alerts SET status = 'cancelled' WHERE status IN ('received', 'dispatching') OR next_dispatch_retry_at IS NOT NULL");
            $connection->executeStatement(
                "INSERT INTO service_heartbeats (name, beat_at) VALUES (?, timezone('UTC', NOW())) ON CONFLICT (name) DO UPDATE SET beat_at = EXCLUDED.beat_at",
                [HeartbeatRepositoryInterface::RECONCILER],
            );

            $client->request(Request::METHOD_GET, '/health/ready');

            self::assertResponseIsSuccessful();
            $body = json_decode((string) $client->getResponse()->getContent(), true);
            self::assertIsArray($body);
            self::assertSame('ok', $body['status']);
            self::assertSame('ok', $body['checks']['database']);
            self::assertSame('ok', $body['checks']['reconciler']);
        } finally {
            $connection->rollBack();
        }
    }

    public function testReadinessIsUnavailableWhenTheReconcilerStopped(): void
    {
        $client = self::createClient();
        $client->disableReboot();
        $connection = self::getContainer()->get(Connection::class);
        self::assertInstanceOf(Connection::class, $connection);

        $connection->beginTransaction();

        try {
            $connection->executeStatement(
                "INSERT INTO service_heartbeats (name, beat_at) VALUES (?, '2001-01-01 00:00:00') ON CONFLICT (name) DO UPDATE SET beat_at = EXCLUDED.beat_at",
                [HeartbeatRepositoryInterface::RECONCILER],
            );

            $client->request(Request::METHOD_GET, '/health/ready');

            self::assertResponseStatusCodeSame(503);
            $body = json_decode((string) $client->getResponse()->getContent(), true);
            self::assertIsArray($body);
            self::assertSame('unavailable', $body['status']);
            self::assertSame('fail', $body['checks']['reconciler']);
        } finally {
            $connection->rollBack();
        }
    }
}
