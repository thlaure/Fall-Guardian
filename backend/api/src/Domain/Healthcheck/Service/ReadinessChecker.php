<?php

declare(strict_types=1);

namespace App\Domain\Healthcheck\Service;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use DateTimeImmutable;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;
use Throwable;

/**
 * Readiness = the service can actually escalate falls: the database answers,
 * no due escalation has been waiting too long, and the reconciler is alive.
 */
final readonly class ReadinessChecker
{
    /** A due escalation older than this means dispatch is stalled. */
    public const int MAX_ESCALATION_BACKLOG_SECONDS = 180;

    /** The reconciler beats every second in watch mode. */
    public const int MAX_RECONCILER_HEARTBEAT_AGE_SECONDS = 60;

    /** Messenger workers beat at most every 15 s; at least one must be fresh. */
    public const int MAX_MESSENGER_HEARTBEAT_AGE_SECONDS = 120;

    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private HeartbeatRepositoryInterface $heartbeatRepository,
        private ClockInterface $clock,
        private LoggerInterface $logger,
    ) {
    }

    /**
     * @return array{ready: bool, checks: array{database: string, escalationBacklog: string, oldestOverdueEscalationAgeSeconds: int|null, reconciler: string, reconcilerHeartbeatAgeSeconds: int|null, messenger: string, messengerHeartbeatAgeSeconds: int|null}}
     */
    public function check(): array
    {
        try {
            $now = $this->clock->now();
            $oldestDueAt = $this->fallAlertRepository->findOldestPendingEscalationDueAt($now);
            $lastBeatAt = $this->heartbeatRepository->lastBeatAt(HeartbeatRepositoryInterface::RECONCILER);
            $lastWorkerBeatAt = $this->heartbeatRepository->lastBeatAtAmong(HeartbeatRepositoryInterface::MESSENGER);
        } catch (Throwable $exception) {
            $this->logger->error('health.database_unavailable', ['exceptionClass' => $exception::class]);

            return [
                'ready' => false,
                'checks' => [
                    'database' => 'fail',
                    'escalationBacklog' => 'unknown',
                    'oldestOverdueEscalationAgeSeconds' => null,
                    'reconciler' => 'unknown',
                    'reconcilerHeartbeatAgeSeconds' => null,
                    'messenger' => 'unknown',
                    'messengerHeartbeatAgeSeconds' => null,
                ],
            ];
        }

        $backlogAge = self::ageSeconds($now, $oldestDueAt);
        $heartbeatAge = self::ageSeconds($now, $lastBeatAt);
        $backlogOk = null === $backlogAge || $backlogAge <= self::MAX_ESCALATION_BACKLOG_SECONDS;
        $reconcilerOk = null !== $heartbeatAge && $heartbeatAge <= self::MAX_RECONCILER_HEARTBEAT_AGE_SECONDS;
        // Pushes are sent by messenger workers: at least one must be alive.
        $workerAge = self::ageSeconds($now, $lastWorkerBeatAt);
        $messengerOk = null !== $workerAge && $workerAge <= self::MAX_MESSENGER_HEARTBEAT_AGE_SECONDS;

        if (!$backlogOk || !$reconcilerOk || !$messengerOk) {
            $this->logger->error('health.escalation_stalled', [
                'oldestOverdueEscalationAgeSeconds' => $backlogAge,
                'reconcilerHeartbeatAgeSeconds' => $heartbeatAge,
                'messengerHeartbeatAgeSeconds' => $workerAge,
            ]);
        }

        return [
            'ready' => $backlogOk && $reconcilerOk && $messengerOk,
            'checks' => [
                'database' => 'ok',
                'escalationBacklog' => $backlogOk ? 'ok' : 'fail',
                'oldestOverdueEscalationAgeSeconds' => $backlogAge,
                'reconciler' => $reconcilerOk ? 'ok' : 'fail',
                'reconcilerHeartbeatAgeSeconds' => $heartbeatAge,
                'messenger' => $messengerOk ? 'ok' : 'fail',
                'messengerHeartbeatAgeSeconds' => $workerAge,
            ],
        ];
    }

    private static function ageSeconds(DateTimeImmutable $now, ?DateTimeImmutable $since): ?int
    {
        return null === $since ? null : max(0, $now->getTimestamp() - $since->getTimestamp());
    }
}
