<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Message\SendFallAlertReminderMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\OverdueAlertReconciler;
use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use App\Entity\FallAlert;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use RuntimeException;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;

final class OverdueAlertReconcilerTest extends TestCase
{
    private MockClock $clock;

    private FallAlertRepositoryInterface&MockObject $repository;

    private HeartbeatRepositoryInterface&MockObject $heartbeats;

    /** @var list<object> */
    private array $dispatched = [];

    private OverdueAlertReconciler $reconciler;

    protected function setUp(): void
    {
        $this->clock = new MockClock('2026-07-23T08:00:31+00:00');
        $this->repository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->heartbeats = $this->createMock(HeartbeatRepositoryInterface::class);
        $bus = $this->createMock(MessageBusInterface::class);
        $bus->method('dispatch')->willReturnCallback(function (object $message): Envelope {
            $this->dispatched[] = $message;

            return new Envelope($message);
        });

        $this->reconciler = new OverdueAlertReconciler($this->repository, $bus, $this->clock, $this->heartbeats, new NullLogger());
    }

    #[Test]
    public function itQueuesEveryDatabaseDispatchCandidateAndRecordsAHeartbeat(): void
    {
        $this->repository->expects(self::once())
            ->method('findDispatchCandidateIds')
            ->with($this->clock->now(), $this->clock->now()->modify('-60 seconds'), 50)
            ->willReturn(['alert-1', 'alert-2']);
        $this->heartbeats->expects(self::once())
            ->method('beat')
            ->with(HeartbeatRepositoryInterface::RECONCILER, $this->clock->now());

        self::assertSame(2, $this->reconciler->reconcile(50));
        self::assertEquals(
            [new SendFallAlertPushMessage('alert-1'), new SendFallAlertPushMessage('alert-2')],
            $this->dispatched,
        );
    }

    #[Test]
    public function itQueuesEachReminderOnlyWhenItsReservationSucceeds(): void
    {
        $this->repository->method('findDispatchCandidateIds')->willReturn([]);
        $this->repository->expects(self::once())
            ->method('findReminderCandidates')
            ->with(
                $this->clock->now(),
                $this->clock->now()->modify(sprintf('-%d seconds', FallAlert::REMINDER_SPACING_SECONDS)),
                FallAlert::MAX_REMINDERS,
                100,
            )
            ->willReturn([['id' => 'alert-1', 'reminderCount' => 0], ['id' => 'alert-2', 'reminderCount' => 1]]);
        // alert-2's reminder was already reserved by a concurrent/previous reconciler run.
        $this->repository->method('claimReminder')->willReturnCallback(
            static fn (string $id, int $expected): bool => 'alert-1' === $id && 0 === $expected,
        );

        $this->repository->expects(self::once())->method('markReminderEnqueued')->with('alert-1', 1);

        self::assertSame(1, $this->reconciler->reconcile());
        self::assertEquals([new SendFallAlertReminderMessage('alert-1', 1)], $this->dispatched);
    }

    #[Test]
    public function aReminderWhoseEnqueueFailsStaysPendingWithoutStoppingTheRun(): void
    {
        $repository = $this->createMock(FallAlertRepositoryInterface::class);
        $repository->method('findDispatchCandidateIds')->willReturn([]);
        $repository->method('findReminderCandidates')->willReturn([['id' => 'alert-1', 'reminderCount' => 0]]);
        $repository->method('claimReminder')->willReturn(true);
        // Not confirmed: the next run finds it through findPendingReminders().
        $repository->expects(self::never())->method('markReminderEnqueued');
        $this->heartbeats->expects(self::once())->method('beat');
        $bus = $this->createMock(MessageBusInterface::class);
        $bus->method('dispatch')->willThrowException(new RuntimeException('Redis connection refused'));

        $reconciler = new OverdueAlertReconciler($repository, $bus, $this->clock, $this->heartbeats, new NullLogger());

        self::assertSame(0, $reconciler->reconcile());
    }

    #[Test]
    public function aPendingReminderIsEnqueuedAgainWithTheSameNumber(): void
    {
        $this->repository->method('findDispatchCandidateIds')->willReturn([]);
        $this->repository->method('findReminderCandidates')->willReturn([]);
        $this->repository->expects(self::once())
            ->method('findPendingReminders')
            ->with($this->clock->now()->modify(sprintf('-%d seconds', FallAlert::REMINDER_ENQUEUE_RETRY_SECONDS)), 100)
            ->willReturn([['id' => 'alert-7', 'reminderNumber' => 2]]);
        $this->repository->expects(self::never())->method('claimReminder');
        $this->repository->expects(self::once())->method('markReminderEnqueued')->with('alert-7', 2);

        self::assertSame(1, $this->reconciler->reconcile());
        self::assertEquals([new SendFallAlertReminderMessage('alert-7', 2)], $this->dispatched);
    }
}
