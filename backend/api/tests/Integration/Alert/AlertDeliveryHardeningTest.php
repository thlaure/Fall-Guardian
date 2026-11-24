<?php

declare(strict_types=1);

namespace App\Tests\Integration\Alert;

use App\Domain\Alert\Handler\SendFallAlertPushMessageHandler;
use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use App\Domain\Alert\Service\CaregiverAlertNotifier;
use App\Domain\Caregiver\Response\CaregiverAlertOutputDTO;
use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\PermanentPushDeliveryException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\AlertAcknowledgement;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Entity\PushAttempt;
use App\Enum\DeviceType;
use App\Enum\FallAlertStatus;
use App\Enum\PushAttemptStatus;
use App\Infrastructure\Persistence\DoctrineAlertAcknowledgementRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverLinkRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverPushTokenRepository;
use App\Infrastructure\Persistence\DoctrineFallAlertRepository;
use App\Infrastructure\Persistence\DoctrinePushAttemptRepository;
use App\Infrastructure\Time\DatabaseClock;
use Closure;
use DateTimeImmutable;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Log\NullLogger;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;

/**
 * Exercises the dispatch handler against the real database: conditional
 * status updates, per-attempt persistence, retries, token clean-up and
 * reminder reservation.
 */
final class AlertDeliveryHardeningTest extends KernelTestCase
{
    private EntityManagerInterface $entityManager;

    private DoctrineFallAlertRepository $alerts;

    protected function setUp(): void
    {
        self::bootKernel();
        $entityManager = self::getContainer()->get(EntityManagerInterface::class);
        $alerts = self::getContainer()->get(DoctrineFallAlertRepository::class);
        self::assertInstanceOf(EntityManagerInterface::class, $entityManager);
        self::assertInstanceOf(DoctrineFallAlertRepository::class, $alerts);
        $this->entityManager = $entityManager;
        $this->alerts = $alerts;
    }

    public function testAnAcknowledgementDuringDispatchIsNeverOverwritten(): void
    {
        [$alert, $caregiver] = $this->dueAlertWithCaregiver('fcm-ok');
        $alertId = $alert->getId()->toRfc4122();
        $connection = $this->entityManager->getConnection();

        // While the push is in flight, the caregiver acknowledges from another
        // process (another PHP worker writing to the same database).
        $this->handler(static function () use ($connection, $alertId, $caregiver): array {
            $connection->executeStatement("UPDATE fall_alerts SET status = 'acknowledged' WHERE id = ?", [$alertId]);
            $connection->executeStatement(
                'INSERT INTO alert_acknowledgements (id, fall_alert_id, caregiver_device_id, acknowledged_at) VALUES (gen_random_uuid(), ?, ?, NOW())',
                [$alertId, $caregiver->getId()->toRfc4122()],
            );

            return ['providerMessageId' => 'msg-1', 'status' => 'sent'];
        })(new SendFallAlertPushMessage($alertId));

        $this->entityManager->clear();
        $reloaded = $this->alerts->findById($alertId);
        self::assertInstanceOf(FallAlert::class, $reloaded);
        self::assertSame(FallAlertStatus::Acknowledged, $reloaded->getStatus());
        self::assertSame([PushAttemptStatus::Sent], $this->attemptStatuses($alertId));
    }

    public function testASuccessfulDispatchIsMarkedSentAndAResumedRoundDoesNotResend(): void
    {
        [$alert] = $this->dueAlertWithCaregiver('fcm-ok');
        $alertId = $alert->getId()->toRfc4122();
        $sends = 0;
        $handler = $this->handler(static function () use (&$sends): array {
            ++$sends;

            return ['providerMessageId' => 'msg', 'status' => 'sent'];
        });

        $handler(new SendFallAlertPushMessage($alertId));
        self::assertSame(FallAlertStatus::Sent, $this->reload($alertId)->getStatus());

        // Simulate a crash after the push but before the outcome: the claim goes
        // stale and the round is resumed by the reconciler.
        $this->entityManager->getConnection()->executeStatement(
            "UPDATE fall_alerts SET status = 'dispatching', dispatch_claimed_at = NOW() - INTERVAL '10 minutes' WHERE id = ?",
            [$alertId],
        );
        $handler(new SendFallAlertPushMessage($alertId));

        self::assertSame(1, $sends, 'A caregiver already notified in this round must not be notified twice.');
        self::assertSame(FallAlertStatus::Sent, $this->reload($alertId)->getStatus());
    }

    public function testATransientFailureIsRetriedByTheReconcilerWithBackoff(): void
    {
        [$alert] = $this->dueAlertWithCaregiver('fcm-flaky');
        $alertId = $alert->getId()->toRfc4122();

        $this->handler(static fn (): array => throw new TransientPushDeliveryException('FCM send failed (HTTP 503).', 'UNAVAILABLE'))(
            new SendFallAlertPushMessage($alertId),
        );

        $failed = $this->reload($alertId);
        self::assertSame(FallAlertStatus::Failed, $failed->getStatus());
        $retryAt = $failed->getNextDispatchRetryAt();
        self::assertInstanceOf(DateTimeImmutable::class, $retryAt);
        self::assertNotContains($alertId, $this->alerts->findDispatchCandidateIds($retryAt->modify('-1 second'), $retryAt->modify('-1 hour'), 1000));
        self::assertContains($alertId, $this->alerts->findDispatchCandidateIds($retryAt, $retryAt->modify('-1 hour'), 1000));

        self::assertSame(FallAlertStatus::Failed, $failed->getLastDispatchOutcome());

        // While the retry round is in flight, clients keep seeing `failed`.
        $this->entityManager->getConnection()->executeStatement('UPDATE fall_alerts SET next_dispatch_retry_at = NOW() - INTERVAL \'1 second\' WHERE id = ?', [$alertId]);
        $now = $this->now();
        $inFlight = $this->alerts->claimForDispatch($alertId, $now, $now->modify('-60 seconds'));
        self::assertInstanceOf(FallAlert::class, $inFlight);
        self::assertSame(FallAlertStatus::Dispatching, $inFlight->getStatus());
        self::assertSame('failed', FallAlertOutputDTO::fromEntity($inFlight)->status);
        self::assertSame('failed', CaregiverAlertOutputDTO::fromEntity($inFlight)->status);
        // Simulate the worker dying mid-round so the next handler run reclaims it.
        $this->entityManager->getConnection()->executeStatement("UPDATE fall_alerts SET dispatch_claimed_at = NOW() - INTERVAL '10 minutes' WHERE id = ?", [$alertId]);

        // Next round succeeds: the alert becomes sent.
        $this->handler(static fn (): array => ['providerMessageId' => 'msg', 'status' => 'sent'])(new SendFallAlertPushMessage($alertId));

        $sent = $this->reload($alertId);
        self::assertSame(FallAlertStatus::Sent, $sent->getStatus());
        self::assertSame(3, $sent->getDispatchAttempts());
        self::assertSame('sent', FallAlertOutputDTO::fromEntity($sent)->status);
        self::assertNull($sent->getNextDispatchRetryAt());
        self::assertSame([PushAttemptStatus::Failed, PushAttemptStatus::Sent], $this->attemptStatuses($alertId));
    }

    public function testAPermanentlyInvalidTokenIsDeleted(): void
    {
        [$alert, $caregiver] = $this->dueAlertWithCaregiver('fcm-dead');
        $tokens = self::getContainer()->get(DoctrineCaregiverPushTokenRepository::class);
        self::assertInstanceOf(DoctrineCaregiverPushTokenRepository::class, $tokens);

        $this->handler(static fn (): array => throw new InvalidPushTokenException('FCM send failed (HTTP 404).', 'UNREGISTERED'))(
            new SendFallAlertPushMessage($alert->getId()->toRfc4122()),
        );

        $this->entityManager->clear();
        self::assertNull($tokens->findByDeviceId($caregiver->getId()->toRfc4122()));
    }

    public function testARejectedMessageKeepsTheTokenAndIsNotRetried(): void
    {
        [$alert, $caregiver] = $this->dueAlertWithCaregiver('fcm-still-valid');
        $tokens = self::getContainer()->get(DoctrineCaregiverPushTokenRepository::class);
        self::assertInstanceOf(DoctrineCaregiverPushTokenRepository::class, $tokens);
        $alertId = $alert->getId()->toRfc4122();

        $this->handler(static fn (): array => throw new PermanentPushDeliveryException('FCM send failed (HTTP 400).', 'INVALID_ARGUMENT'))(
            new SendFallAlertPushMessage($alertId),
        );

        $this->entityManager->clear();
        self::assertInstanceOf(CaregiverPushToken::class, $tokens->findByDeviceId($caregiver->getId()->toRfc4122()));
        $failed = $this->reload($alertId);
        self::assertSame(FallAlertStatus::Failed, $failed->getStatus());
        self::assertNull($failed->getNextDispatchRetryAt());
    }

    public function testATokenReRegisteredMeanwhileIsNotDeleted(): void
    {
        [, $caregiver] = $this->dueAlertWithCaregiver('fcm-old');
        $tokens = self::getContainer()->get(DoctrineCaregiverPushTokenRepository::class);
        self::assertInstanceOf(DoctrineCaregiverPushTokenRepository::class, $tokens);
        $token = $tokens->findByDevice($caregiver);
        self::assertInstanceOf(CaregiverPushToken::class, $token);
        $token->update('fcm-new');
        $tokens->save($token);

        self::assertFalse($tokens->deleteIfUnchanged($caregiver, 'fcm-old'));
        self::assertTrue($tokens->deleteIfUnchanged($caregiver, 'fcm-new'));
    }

    public function testRemindersAreReservedExactlyOncePerNumberAndStopAfterAcknowledgement(): void
    {
        [$alert] = $this->dueAlertWithCaregiver('fcm-ok');
        $alertId = $alert->getId()->toRfc4122();
        $this->handler(static fn (): array => ['providerMessageId' => 'msg', 'status' => 'sent'])(new SendFallAlertPushMessage($alertId));
        $connection = $this->entityManager->getConnection();
        $connection->executeStatement("UPDATE fall_alerts SET acknowledgement_deadline_at = NOW() - INTERVAL '1 second' WHERE id = ?", [$alertId]);
        $now = $this->now();

        self::assertContains(['id' => $alertId, 'reminderCount' => 0], $this->alerts->findReminderCandidates($now, $now->modify('-120 seconds'), 3, 1000));
        self::assertTrue($this->alerts->claimReminder($alertId, 0, $now));
        // A second reconciler (or a restart) racing on the same reminder loses.
        self::assertFalse($this->alerts->claimReminder($alertId, 0, $now));
        // Spacing: not a candidate again right away.
        self::assertNotContains($alertId, array_column($this->alerts->findReminderCandidates($now, $now->modify('-120 seconds'), 3, 1000), 'id'));

        // A deferred reminder is given back and can be reserved again.
        self::assertTrue($this->alerts->releaseReminder($alertId, 1));
        self::assertFalse($this->alerts->releaseReminder($alertId, 1), 'Only the latest reserved reminder can be released.');
        self::assertTrue($this->alerts->claimReminder($alertId, 0, $now));

        $connection->executeStatement("UPDATE fall_alerts SET status = 'acknowledged' WHERE id = ?", [$alertId]);
        self::assertFalse($this->alerts->claimReminder($alertId, 1, $now->modify('+5 minutes')));
        self::assertNotContains($alertId, array_column($this->alerts->findReminderCandidates($now->modify('+5 minutes'), $now->modify('+3 minutes'), 3, 1000), 'id'));
    }

    public function testAReservedReminderWhoseEnqueueFailedIsRecoveredWithTheSameNumber(): void
    {
        [$alert] = $this->dueAlertWithCaregiver('fcm-ok');
        $alertId = $alert->getId()->toRfc4122();
        $this->handler(static fn (): array => ['providerMessageId' => 'msg', 'status' => 'sent'])(new SendFallAlertPushMessage($alertId));
        $this->entityManager->getConnection()->executeStatement("UPDATE fall_alerts SET acknowledgement_deadline_at = NOW() - INTERVAL '1 second' WHERE id = ?", [$alertId]);
        $now = $this->now();

        // Reserved, then the queue was unavailable: never confirmed.
        self::assertTrue($this->alerts->claimReminder($alertId, 0, $now));
        self::assertNotContains($alertId, array_column($this->alerts->findPendingReminders($now->modify('-10 seconds'), 1000), 'id'), 'Too fresh: the reserving run may still be enqueueing.');
        self::assertContains(['id' => $alertId, 'reminderNumber' => 1], $this->alerts->findPendingReminders($now->modify('+10 seconds'), 1000));
        // The next number is never reserved while number 1 is pending, even after the spacing.
        self::assertNotContains($alertId, array_column($this->alerts->findReminderCandidates($now->modify('+5 minutes'), $now->modify('+3 minutes'), 3, 1000), 'id'));

        $this->alerts->markReminderEnqueued($alertId, 1);
        self::assertNotContains($alertId, array_column($this->alerts->findPendingReminders($now->modify('+10 seconds'), 1000), 'id'));
        self::assertContains(['id' => $alertId, 'reminderCount' => 1], $this->alerts->findReminderCandidates($now->modify('+5 minutes'), $now->modify('+3 minutes'), 3, 1000));
        self::assertSame(1, $this->reload($alertId)->getReminderEnqueuedCount());

        // A deferred (released) reminder is no longer pending either.
        self::assertTrue($this->alerts->releaseReminder($alertId, 1));
        self::assertSame(0, $this->reload($alertId)->getReminderEnqueuedCount());
        self::assertNotContains($alertId, array_column($this->alerts->findPendingReminders($now->modify('+10 seconds'), 1000), 'id'));
        $this->alerts->markReminderEnqueued('not-a-uuid', 1);
    }

    public function testAlertsDeliveredLongAgoAreNeverReminded(): void
    {
        [$alert] = $this->dueAlertWithCaregiver('fcm-ok');
        $alertId = $alert->getId()->toRfc4122();
        $this->entityManager->getConnection()->executeStatement(
            "UPDATE fall_alerts SET status = 'sent', acknowledgement_deadline_at = NOW() - INTERVAL '2 days' WHERE id = ?",
            [$alertId],
        );
        $now = $this->now();

        self::assertNotContains($alertId, array_column($this->alerts->findReminderCandidates($now, $now, 3, 1000), 'id'));
    }

    public function testMalformedIdentifiersAreTreatedAsUnknown(): void
    {
        $now = $this->now();

        self::assertNull($this->alerts->findById('not-a-uuid'));
        self::assertNull($this->alerts->claimForDispatch('not-a-uuid', $now, $now));
        self::assertFalse($this->alerts->completeDispatch('not-a-uuid', FallAlertStatus::Sent, null));
        self::assertFalse($this->alerts->claimReminder('not-a-uuid', 0, $now));
        $this->alerts->touchDispatchClaim('not-a-uuid', $now);
    }

    public function testAcknowledgementSummaryCountsEveryCaregiverAndKeepsTheFirstTime(): void
    {
        [$alert, $caregiver] = $this->dueAlertWithCaregiver('fcm-ok');
        $other = $this->caregiverDevice();
        $acks = self::getContainer()->get(DoctrineAlertAcknowledgementRepository::class);
        self::assertInstanceOf(DoctrineAlertAcknowledgementRepository::class, $acks);
        $acks->save(new AlertAcknowledgement($alert, $other, new DateTimeImmutable('2026-07-23T08:02:00+00:00')));
        $acks->save(new AlertAcknowledgement($alert, $caregiver, new DateTimeImmutable('2026-07-23T08:01:00+00:00')));

        $summary = $acks->summarizeByAlerts([$alert]);

        self::assertSame(2, $summary[$alert->getId()->toRfc4122()]['count']);
        self::assertEquals(new DateTimeImmutable('2026-07-23T08:01:00+00:00'), $summary[$alert->getId()->toRfc4122()]['firstAcknowledgedAt']);
        self::assertSame([], $acks->summarizeByAlerts([]));
    }

    public function testTheOldestPendingEscalationIsReported(): void
    {
        $device = $this->protectedDevice();
        $receivedAt = new DateTimeImmutable('2001-01-01T00:00:00+00:00');
        $alert = new FallAlert($device, 'backlog-'.bin2hex(random_bytes(6)), $receivedAt, 'en', null, null, $receivedAt);
        $this->alerts->save($alert);

        try {
            $oldest = $this->alerts->findOldestPendingEscalationDueAt($this->now());

            self::assertInstanceOf(DateTimeImmutable::class, $oldest);
            self::assertLessThanOrEqual($alert->getCancelDeadlineAt(), $oldest);
        } finally {
            // Never leave a due escalation behind: other tests query them globally.
            $this->entityManager->getConnection()->executeStatement("UPDATE fall_alerts SET status = 'cancelled' WHERE id = ?", [$alert->getId()->toRfc4122()]);
        }
    }

    /**
     * @param Closure(string, FallAlertPushPayload): array{providerMessageId: ?string, status: string} $send
     */
    private function handler(Closure $send): SendFallAlertPushMessageHandler
    {
        $gateway = new readonly class($send) implements PushGatewayInterface {
            public function __construct(private Closure $send)
            {
            }

            public function getProviderName(): string
            {
                return 'test';
            }

            public function send(string $fcmToken, FallAlertPushPayload $payload): array
            {
                return ($this->send)($fcmToken, $payload);
            }

            public function sendLinkRevoked(string $fcmToken): array
            {
                return ['providerMessageId' => null, 'status' => 'sent'];
            }
        };

        $container = self::getContainer();
        $links = $container->get(DoctrineCaregiverLinkRepository::class);
        $tokens = $container->get(DoctrineCaregiverPushTokenRepository::class);
        $attempts = $container->get(DoctrinePushAttemptRepository::class);
        $clock = $container->get(DatabaseClock::class);
        self::assertInstanceOf(DoctrineCaregiverLinkRepository::class, $links);
        self::assertInstanceOf(DoctrineCaregiverPushTokenRepository::class, $tokens);
        self::assertInstanceOf(DoctrinePushAttemptRepository::class, $attempts);
        self::assertInstanceOf(DatabaseClock::class, $clock);

        return new SendFallAlertPushMessageHandler(
            $this->alerts,
            new CaregiverAlertNotifier($links, $tokens, $attempts, $gateway, new NullLogger()),
            $clock,
            new NullLogger(),
        );
    }

    /** @return array{0: FallAlert, 1: Device} */
    private function dueAlertWithCaregiver(string $fcmToken): array
    {
        $protected = $this->protectedDevice();
        $caregiver = $this->caregiverDevice();
        $link = new CaregiverLink($protected, $caregiver);
        $link->renameProtectedPerson('Mamie');
        $this->entityManager->persist($link);
        $this->entityManager->persist(new CaregiverPushToken($caregiver, $fcmToken));

        $receivedAt = $this->now()->modify('-40 seconds');
        $alert = new FallAlert($protected, 'hardening-'.bin2hex(random_bytes(6)), $receivedAt, 'en', 48.8, 2.3, $receivedAt);
        $this->entityManager->persist($alert);
        $this->entityManager->flush();

        return [$alert, $caregiver];
    }

    private function protectedDevice(): Device
    {
        $device = new Device('protected-'.bin2hex(random_bytes(6)), bin2hex(random_bytes(32)), 'ios', '1.0.0');
        $this->entityManager->persist($device);
        $this->entityManager->flush();

        return $device;
    }

    private function caregiverDevice(): Device
    {
        $device = new Device('caregiver-'.bin2hex(random_bytes(6)), bin2hex(random_bytes(32)), 'android', '1.0.0');
        $device->setDeviceType(DeviceType::Caregiver);
        $this->entityManager->persist($device);
        $this->entityManager->flush();

        return $device;
    }

    private function reload(string $alertId): FallAlert
    {
        $this->entityManager->clear();
        $alert = $this->alerts->findById($alertId);
        self::assertInstanceOf(FallAlert::class, $alert);

        return $alert;
    }

    /** @return list<PushAttemptStatus> */
    private function attemptStatuses(string $alertId): array
    {
        /** @var list<PushAttempt> $attempts */
        $attempts = $this->entityManager->getRepository(PushAttempt::class)
            ->createQueryBuilder('attempt')
            ->andWhere('attempt.fallAlert = :alert')
            ->setParameter('alert', $alertId)
            ->orderBy('attempt.queuedAt', 'ASC')
            ->addOrderBy('attempt.id', 'ASC')
            ->getQuery()
            ->getResult();

        return array_map(static fn (PushAttempt $attempt): PushAttemptStatus => $attempt->getStatus(), $attempts);
    }

    private function now(): DateTimeImmutable
    {
        $clock = self::getContainer()->get(DatabaseClock::class);
        self::assertInstanceOf(DatabaseClock::class, $clock);

        return $clock->now();
    }
}
