<?php

declare(strict_types=1);

namespace App\Tests\Integration\Infrastructure;

use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use App\Entity\CaregiverInvite;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Infrastructure\Persistence\DoctrineCaregiverInviteRepository;
use App\Infrastructure\Persistence\DoctrineHeartbeatRepository;
use App\Infrastructure\Persistence\DoctrineRetentionRepository;
use App\Infrastructure\RateLimit\FixedWindowEndpointRateLimiter;
use DateTimeImmutable;
use Doctrine\DBAL\Connection;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;

final class OperationalHardeningTest extends KernelTestCase
{
    private EntityManagerInterface $entityManager;

    private Connection $connection;

    protected function setUp(): void
    {
        self::bootKernel();
        $entityManager = self::getContainer()->get(EntityManagerInterface::class);
        self::assertInstanceOf(EntityManagerInterface::class, $entityManager);
        $this->entityManager = $entityManager;
        $this->connection = $entityManager->getConnection();
    }

    public function testHashedInvitesAreFoundByHashOnlyAndLegacyRowsByPlaintextOnly(): void
    {
        $invites = self::getContainer()->get(DoctrineCaregiverInviteRepository::class);
        self::assertInstanceOf(DoctrineCaregiverInviteRepository::class, $invites);
        $device = $this->device();
        $hash = hash('sha256', 'hashed-'.bin2hex(random_bytes(6)));
        $hashed = CaregiverInvite::issueHashed($device, $hash, new DateTimeImmutable('+30 minutes'));
        $invites->save($hashed);
        $legacyCode = strtoupper(bin2hex(random_bytes(4)));
        $legacy = new CaregiverInvite($device, $legacyCode, new DateTimeImmutable('+30 minutes'));
        $invites->save($legacy);
        $expiredHash = hash('sha256', 'expired-'.bin2hex(random_bytes(6)));
        $invites->save(CaregiverInvite::issueHashed($device, $expiredHash, new DateTimeImmutable('-1 minute')));

        self::assertSame($hashed, $invites->findActiveByCodeHash($hash));
        self::assertNull($invites->findActiveByCodeHash($expiredHash));
        self::assertSame($legacy, $invites->findActiveLegacyByPlainCode($legacyCode));
        self::assertNull($invites->findActiveLegacyByPlainCode($hash), 'A hash must never be accepted as a plaintext code.');
        self::assertNull($this->connection->fetchOne('SELECT code FROM caregiver_invites WHERE id = ?', [$hashed->getId()->toRfc4122()]));
    }

    public function testRateLimiterCreatesBucketsRaceFreeAndStillEnforcesTheLimit(): void
    {
        $limiter = new FixedWindowEndpointRateLimiter($this->entityManager, new RequestStack());
        $subject = 'subject-'.bin2hex(random_bytes(6));
        // A concurrent request created the bucket between our check and insert.
        $this->connection->executeStatement(
            'INSERT INTO rate_limit_buckets (id, window_start_at, hits) VALUES (?, NOW(), 0)',
            [hash('sha256', 'integration|'.$subject)],
        );

        $limiter->consume('integration', 2, 60, $subject);
        $limiter->consume('integration', 2, 60, $subject);

        $this->expectException(TooManyRequestsHttpException::class);
        $limiter->consume('integration', 2, 60, $subject);
    }

    public function testHeartbeatsAreUpserted(): void
    {
        $heartbeats = self::getContainer()->get(HeartbeatRepositoryInterface::class);
        self::assertInstanceOf(DoctrineHeartbeatRepository::class, $heartbeats);

        $heartbeats->beat('integration-test', new DateTimeImmutable('2026-01-01T00:00:00+00:00'));
        $heartbeats->beat('integration-test', new DateTimeImmutable('2026-01-01T00:00:05+00:00'));

        self::assertEquals(new DateTimeImmutable('2026-01-01T00:00:05+00:00'), $heartbeats->lastBeatAt('integration-test'));
        self::assertNull($heartbeats->lastBeatAt('never-beat'));
    }

    public function testRetentionDeletesOnlyClosedDataPastItsPeriod(): void
    {
        $retention = new DoctrineRetentionRepository($this->connection);
        $device = $this->device();
        $old = new DateTimeImmutable('2005-06-01T00:00:00+00:00');
        $recent = new DateTimeImmutable('2015-06-01T00:00:00+00:00');

        $oldClosed = $this->alert($device, $old, 'sent');
        $oldRetrying = $this->alert($device, $old, 'failed', retryScheduled: true);
        $oldReceived = $this->alert($device, $old, 'received');
        $recentClosed = $this->alert($device, $recent, 'acknowledged');
        $this->connection->executeStatement(
            "INSERT INTO push_attempts (id, fall_alert_id, caregiver_device_id, provider, status, retry_count, queued_at, reminder_number) VALUES (gen_random_uuid(), ?, ?, 'fake', 'sent', 0, '2005-06-01 00:00:31', 0)",
            [$oldClosed, $device->getId()->toRfc4122()],
        );
        $this->connection->executeStatement(
            'INSERT INTO alert_acknowledgements (id, fall_alert_id, caregiver_device_id, acknowledged_at) VALUES (gen_random_uuid(), ?, ?, ?)',
            [$oldClosed, $device->getId()->toRfc4122(), '2005-06-01 00:01:00'],
        );

        try {
            $this->assertRetentionOfAlerts($retention, $oldClosed, $oldRetrying, $oldReceived, $recentClosed);
        } finally {
            // Never leave due escalations behind: other tests query them globally.
            $this->connection->executeStatement("UPDATE fall_alerts SET status = 'cancelled', next_dispatch_retry_at = NULL WHERE id IN (?, ?)", [$oldRetrying, $oldReceived]);
        }
    }

    private function assertRetentionOfAlerts(DoctrineRetentionRepository $retention, string $oldClosed, string $oldRetrying, string $oldReceived, string $recentClosed): void
    {
        $cutoff = new DateTimeImmutable('2010-01-01T00:00:00+00:00');
        self::assertGreaterThanOrEqual(1, $retention->deleteClosedAlertsBefore($cutoff, 500));
        self::assertFalse($this->exists('fall_alerts', $oldClosed));
        self::assertSame(0, (int) $this->connection->fetchOne('SELECT COUNT(*) FROM push_attempts WHERE fall_alert_id = ?', [$oldClosed]));
        self::assertSame(0, (int) $this->connection->fetchOne('SELECT COUNT(*) FROM alert_acknowledgements WHERE fall_alert_id = ?', [$oldClosed]));
        self::assertTrue($this->exists('fall_alerts', $oldRetrying), 'An alert with a pending retry is still active.');
        self::assertTrue($this->exists('fall_alerts', $oldReceived), 'An alert still in its escalation flow is never deleted.');
        self::assertTrue($this->exists('fall_alerts', $recentClosed));

        self::assertGreaterThanOrEqual(1, $retention->eraseLocationOfClosedAlertsBefore(new DateTimeImmutable('2020-01-01T00:00:00+00:00'), 500));
        self::assertSame([null, null], array_values($this->connection->fetchAssociative('SELECT latitude, longitude FROM fall_alerts WHERE id = ?', [$recentClosed]) ?: []));
        self::assertNotNull($this->connection->fetchOne('SELECT latitude FROM fall_alerts WHERE id = ?', [$oldReceived]));
    }

    public function testRetentionDeletesFinishedInvitesEnrollmentsAndStaleRateLimitBuckets(): void
    {
        $retention = new DoctrineRetentionRepository($this->connection);
        $device = $this->device();
        $oldExpired = CaregiverInvite::issueHashed($device, hash('sha256', bin2hex(random_bytes(8))), new DateTimeImmutable('2005-01-01T00:00:00+00:00'));
        $live = CaregiverInvite::issueHashed($device, hash('sha256', bin2hex(random_bytes(8))), new DateTimeImmutable('+30 minutes'));
        $this->entityManager->persist($oldExpired);
        $this->entityManager->persist($live);
        $this->entityManager->flush();
        $oldBucket = 'old-'.bin2hex(random_bytes(6));
        $freshBucket = 'fresh-'.bin2hex(random_bytes(6));
        $this->connection->executeStatement("INSERT INTO rate_limit_buckets (id, window_start_at, hits) VALUES (?, '2005-01-01 00:00:00', 3), (?, NOW(), 1)", [$oldBucket, $freshBucket]);

        $cutoff = new DateTimeImmutable('2010-01-01T00:00:00+00:00');
        self::assertGreaterThanOrEqual(1, $retention->deleteFinishedInvitesBefore($cutoff, 500));
        self::assertGreaterThanOrEqual(0, $retention->deleteFinishedCompanionEnrollmentsBefore($cutoff, 500));
        self::assertGreaterThanOrEqual(1, $retention->deleteRateLimitBucketsBefore($cutoff, 500));

        self::assertFalse($this->exists('caregiver_invites', $oldExpired->getId()->toRfc4122()));
        self::assertTrue($this->exists('caregiver_invites', $live->getId()->toRfc4122()));
        self::assertFalse($this->exists('rate_limit_buckets', $oldBucket));
        self::assertTrue($this->exists('rate_limit_buckets', $freshBucket));
    }

    private function alert(Device $device, DateTimeImmutable $receivedAt, string $status, bool $retryScheduled = false): string
    {
        $alert = new FallAlert($device, 'retention-'.bin2hex(random_bytes(6)), $receivedAt, 'en', 48.8, 2.3, $receivedAt);
        $this->entityManager->persist($alert);
        $this->entityManager->flush();
        $id = $alert->getId()->toRfc4122();
        $this->connection->executeStatement(
            'UPDATE fall_alerts SET status = ?, next_dispatch_retry_at = ? WHERE id = ?',
            [$status, $retryScheduled ? '2099-01-01 00:00:00' : null, $id],
        );

        return $id;
    }

    private function exists(string $table, string $id): bool
    {
        return false !== $this->connection->fetchOne(sprintf('SELECT 1 FROM %s WHERE id = ?', $table), [$id]);
    }

    private function device(): Device
    {
        $device = new Device('retention-'.bin2hex(random_bytes(6)), bin2hex(random_bytes(32)), 'ios', '1.0.0');
        $this->entityManager->persist($device);
        $this->entityManager->flush();

        return $device;
    }
}
