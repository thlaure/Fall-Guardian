<?php

declare(strict_types=1);

namespace App\Infrastructure\Messenger;

use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\Messenger\Event\WorkerRunningEvent;
use Throwable;

/**
 * Records a messenger worker heartbeat at most every few seconds. The worker
 * dispatches WorkerRunningEvent on every loop iteration, idle or not, so a
 * stale heartbeat means the worker is stuck or gone.
 */
final class WorkerHeartbeatSubscriber implements EventSubscriberInterface
{
    private const int MIN_INTERVAL_SECONDS = 15;

    private int $lastBeatAt = 0;

    public function __construct(
        private readonly HeartbeatRepositoryInterface $heartbeatRepository,
        private readonly ClockInterface $clock,
        private readonly LoggerInterface $logger,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [WorkerRunningEvent::class => 'onWorkerRunning'];
    }

    public function onWorkerRunning(WorkerRunningEvent $event): void
    {
        $now = time();

        if ($now - $this->lastBeatAt < self::MIN_INTERVAL_SECONDS) {
            return;
        }

        $this->lastBeatAt = $now;

        try {
            $this->heartbeatRepository->beat(HeartbeatRepositoryInterface::MESSENGER, $this->clock->now());
        } catch (Throwable $exception) {
            // A heartbeat failure must never stop alert delivery.
            $this->logger->warning('worker.heartbeat_failed', ['exceptionClass' => $exception::class]);
        }
    }
}
