<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Command\ReconcileOverdueAlertsCommand;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\OverdueAlertReconciler;
use App\Domain\Healthcheck\Port\HeartbeatRepositoryInterface;
use App\Domain\Retention\Port\RetentionRepositoryInterface;
use App\Domain\Retention\Service\DataRetentionService;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use ReflectionMethod;
use RuntimeException;
use Stringable;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Console\Tester\CommandTester;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;

final class ReconcileOverdueAlertsCommandTest extends TestCase
{
    #[Test]
    public function aSingleRunReconcilesWithoutPurging(): void
    {
        $alerts = $this->createMock(FallAlertRepositoryInterface::class);
        $alerts->method('findDispatchCandidateIds')->willReturn(['alert-1']);
        $bus = $this->createMock(MessageBusInterface::class);
        $bus->method('dispatch')->willReturnCallback(static fn (object $message): Envelope => new Envelope($message));
        $retention = $this->createMock(RetentionRepositoryInterface::class);
        $retention->expects($this->never())->method('deleteClosedAlertsBefore');

        $command = new ReconcileOverdueAlertsCommand(
            new OverdueAlertReconciler($alerts, $bus, new MockClock(), $this->createMock(HeartbeatRepositoryInterface::class), new NullLogger()),
            new DataRetentionService($retention, new MockClock(), new NullLogger(), 365, 30),
            new NullLogger(),
        );
        $tester = new CommandTester($command);

        self::assertSame(0, $tester->execute([]));
        self::assertStringContainsString('Queued 1 overdue alert dispatch(es) or reminder(s).', $tester->getDisplay());
    }

    #[Test]
    public function aRetentionFailureIsLoggedAndNeverStopsEscalation(): void
    {
        $retention = $this->createMock(RetentionRepositoryInterface::class);
        $retention->method('deleteClosedAlertsBefore')->willThrowException(new RuntimeException('lock timeout'));
        $logger = new class extends \Psr\Log\AbstractLogger {
            /** @var list<string> */
            public array $messages = [];

            public function log($level, Stringable|string $message, array $context = []): void
            {
                $this->messages[] = $level.':'.$message;
            }
        };
        $command = new ReconcileOverdueAlertsCommand(
            new OverdueAlertReconciler($this->createMock(FallAlertRepositoryInterface::class), $this->createMock(MessageBusInterface::class), new MockClock(), $this->createMock(HeartbeatRepositoryInterface::class), new NullLogger()),
            new DataRetentionService($retention, new MockClock(), new NullLogger(), 365, 30),
            $logger,
        );

        self::assertTrue(new ReflectionMethod($command, 'runRetention')->invoke($command));
        self::assertSame(['error:retention.failed'], $logger->messages);
    }

    #[Test]
    public function aRetentionRunInsideTheLoopIsTimeBoxed(): void
    {
        $elapsed = 0.0;
        $retention = $this->createMock(RetentionRepositoryInterface::class);
        $retention->method('deleteRateLimitBucketsBefore')->willReturnCallback(static function () use (&$elapsed): int {
            $elapsed += 1.5;

            return 500;
        });
        $command = new ReconcileOverdueAlertsCommand(
            new OverdueAlertReconciler($this->createMock(FallAlertRepositoryInterface::class), $this->createMock(MessageBusInterface::class), new MockClock(), $this->createMock(HeartbeatRepositoryInterface::class), new NullLogger()),
            new DataRetentionService($retention, new MockClock(), new NullLogger(), 365, 30, static function () use (&$elapsed): float {
                return $elapsed;
            }),
            new NullLogger(),
        );

        // Budget is 2 s: two 1.5 s batches run, then the run yields back to escalation.
        self::assertFalse(new ReflectionMethod($command, 'runRetention')->invoke($command));
        self::assertEqualsWithDelta(3.0, $elapsed, 0.001);
        self::assertSame(2.0, ReconcileOverdueAlertsCommand::RETENTION_TIME_BUDGET_SECONDS);
    }
}
