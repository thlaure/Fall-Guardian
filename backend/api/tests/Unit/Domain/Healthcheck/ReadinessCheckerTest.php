<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Healthcheck;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Healthcheck\Command\HeartbeatCheckCommand;
use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use App\Domain\Healthcheck\Service\ReadinessChecker;
use App\Domain\Healthcheck\Service\WorkerHeartbeatName;
use App\Infrastructure\Messenger\WorkerHeartbeatSubscriber;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use RuntimeException;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Tester\CommandTester;
use Symfony\Component\Messenger\Event\WorkerRunningEvent;
use Symfony\Component\Messenger\Worker;

final class ReadinessCheckerTest extends TestCase
{
    private MockClock $clock;

    protected function setUp(): void
    {
        $this->clock = new MockClock('2026-11-21T12:00:00+00:00');
    }

    #[Test]
    public function itIsReadyWithAFreshReconcilerAndNoBacklog(): void
    {
        $result = $this->checker(null, $this->clock->now()->modify('-2 seconds'))->check();

        self::assertTrue($result['ready']);
        self::assertSame('ok', $result['checks']['database']);
        self::assertNull($result['checks']['oldestOverdueEscalationAgeSeconds']);
        self::assertSame(2, $result['checks']['reconcilerHeartbeatAgeSeconds']);
    }

    #[Test]
    public function itIsNotReadyWhenAnEscalationHasBeenDueForTooLong(): void
    {
        $result = $this->checker($this->clock->now()->modify('-181 seconds'), $this->clock->now())->check();

        self::assertFalse($result['ready']);
        self::assertSame('fail', $result['checks']['escalationBacklog']);
        self::assertSame(181, $result['checks']['oldestOverdueEscalationAgeSeconds']);
    }

    #[Test]
    public function itToleratesARecentlyDueEscalation(): void
    {
        self::assertTrue($this->checker($this->clock->now()->modify('-20 seconds'), $this->clock->now())->check()['ready']);
    }

    #[Test]
    public function itIsNotReadyWhenTheReconcilerIsStaleOrNeverRan(): void
    {
        self::assertFalse($this->checker(null, $this->clock->now()->modify('-61 seconds'))->check()['ready']);
        $neverRan = $this->checker(null, null)->check();
        self::assertFalse($neverRan['ready']);
        self::assertSame('fail', $neverRan['checks']['reconciler']);
    }

    #[Test]
    public function itRequiresAtLeastOneLiveMessengerWorker(): void
    {
        $noWorker = $this->checker(null, $this->clock->now(), null)->check();
        self::assertFalse($noWorker['ready']);
        self::assertSame('fail', $noWorker['checks']['messenger']);

        $staleWorkers = $this->checker(null, $this->clock->now(), $this->clock->now()->modify('-121 seconds'))->check();
        self::assertFalse($staleWorkers['ready']);
        self::assertSame(121, $staleWorkers['checks']['messengerHeartbeatAgeSeconds']);

        self::assertSame('ok', $this->checker(null, $this->clock->now())->check()['checks']['messenger']);
    }

    #[Test]
    public function itIsNotReadyWhenTheDatabaseIsUnavailable(): void
    {
        $alerts = $this->createMock(FallAlertRepositoryInterface::class);
        $alerts->method('findOldestPendingEscalationDueAt')->willThrowException(new RuntimeException('connection refused'));

        $result = new ReadinessChecker($alerts, $this->createMock(HeartbeatRepositoryInterface::class), $this->clock, new NullLogger())->check();

        self::assertFalse($result['ready']);
        self::assertSame('fail', $result['checks']['database']);
    }

    #[Test]
    public function theHeartbeatCommandFailsOnMissingOrStaleHeartbeats(): void
    {
        $heartbeats = $this->createMock(HeartbeatRepositoryInterface::class);
        $heartbeats->method('lastBeatAt')->willReturnMap([
            [HeartbeatRepositoryInterface::RECONCILER, $this->clock->now()->modify('-5 seconds')],
            // Another worker container is alive, but this container's worker never beat.
            [WorkerHeartbeatName::forHost('other-container'), $this->clock->now()],
            [WorkerHeartbeatName::forThisHost(), null],
        ]);
        $tester = new CommandTester(new HeartbeatCheckCommand($heartbeats, $this->clock));

        self::assertSame(Command::SUCCESS, $tester->execute(['component' => 'alert_reconciler', '--max-age' => '60']));
        self::assertSame(Command::FAILURE, $tester->execute(['component' => 'alert_reconciler', '--max-age' => '4']));
        self::assertSame(Command::FAILURE, $tester->execute(['component' => 'messenger']));
        self::assertSame(Command::INVALID, $tester->execute(['component' => 'unknown']));
    }

    #[Test]
    public function theHeartbeatCommandFailsWhenTheDatabaseIsDown(): void
    {
        $heartbeats = $this->createMock(HeartbeatRepositoryInterface::class);
        $heartbeats->method('lastBeatAt')->willThrowException(new RuntimeException('down'));

        self::assertSame(Command::FAILURE, new CommandTester(new HeartbeatCheckCommand($heartbeats, $this->clock))->execute(['component' => 'messenger']));
    }

    #[Test]
    public function theWorkerHeartbeatIsThrottledAndNeverBreaksTheWorker(): void
    {
        $heartbeats = $this->createMock(HeartbeatRepositoryInterface::class);
        $heartbeats->expects($this->once())
            ->method('beat')
            ->with(WorkerHeartbeatName::forThisHost(), $this->clock->now())
            ->willThrowException(new RuntimeException('database down'));
        $subscriber = new WorkerHeartbeatSubscriber($heartbeats, $this->clock, new NullLogger());
        $event = new WorkerRunningEvent($this->createMock(Worker::class), true);

        $subscriber->onWorkerRunning($event);
        $subscriber->onWorkerRunning($event);

        self::assertArrayHasKey(WorkerRunningEvent::class, WorkerHeartbeatSubscriber::getSubscribedEvents());
    }

    private function checker(?DateTimeImmutable $oldestDueAt, ?DateTimeImmutable $lastBeatAt, ?DateTimeImmutable $lastWorkerBeatAt = new DateTimeImmutable('2026-11-21T11:59:50+00:00')): ReadinessChecker
    {
        $alerts = $this->createMock(FallAlertRepositoryInterface::class);
        $alerts->method('findOldestPendingEscalationDueAt')->willReturn($oldestDueAt);
        $heartbeats = $this->createMock(HeartbeatRepositoryInterface::class);
        $heartbeats->method('lastBeatAt')->willReturn($lastBeatAt);
        $heartbeats->method('lastBeatAtAmong')->with(HeartbeatRepositoryInterface::MESSENGER)->willReturn($lastWorkerBeatAt);

        return new ReadinessChecker($alerts, $heartbeats, $this->clock, new NullLogger());
    }

    #[Test]
    public function workerHeartbeatsAreNamedPerHost(): void
    {
        self::assertSame('messenger:abc123', WorkerHeartbeatName::forHost('abc123'));
        self::assertSame('messenger:unknown', WorkerHeartbeatName::forHost(''));
        self::assertStringStartsWith('messenger:', WorkerHeartbeatName::forThisHost());
    }
}
