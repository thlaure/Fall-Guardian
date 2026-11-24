<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Retention;

use App\Domain\Retention\Command\PurgeExpiredDataCommand;
use App\Domain\Retention\Port\RetentionRepositoryInterface;
use App\Domain\Retention\Service\DataRetentionService;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Console\Tester\CommandTester;

final class DataRetentionServiceTest extends TestCase
{
    #[Test]
    public function itAppliesEachRetentionPeriodToItsCategory(): void
    {
        $clock = new MockClock('2026-11-21T12:00:00+00:00');
        $repository = $this->createMock(RetentionRepositoryInterface::class);
        $repository->expects($this->once())->method('deleteClosedAlertsBefore')
            ->with(new DateTimeImmutable('2025-11-21T12:00:00+00:00'), 500)->willReturn(3);
        $repository->expects($this->once())->method('eraseLocationOfClosedAlertsBefore')
            ->with(new DateTimeImmutable('2026-10-22T12:00:00+00:00'), 500)->willReturn(4);
        $repository->expects($this->once())->method('deleteFinishedInvitesBefore')
            ->with(new DateTimeImmutable('2026-11-14T12:00:00+00:00'), 500)->willReturn(5);
        $repository->expects($this->once())->method('deleteFinishedCompanionEnrollmentsBefore')
            ->with(new DateTimeImmutable('2026-11-14T12:00:00+00:00'), 500)->willReturn(6);
        $repository->expects($this->once())->method('deleteRateLimitBucketsBefore')
            ->with(new DateTimeImmutable('2026-11-20T12:00:00+00:00'), 500)->willReturn(7);

        $result = new DataRetentionService($repository, $clock, new NullLogger(), 365, 30)->purge();

        self::assertSame([
            'completed' => true,
            'deletedRateLimitBuckets' => 7,
            'deletedHeartbeats' => 0,
            'deletedInvites' => 5,
            'deletedEnrollments' => 6,
            'erasedLocations' => 4,
            'deletedAlerts' => 3,
        ], $result);
    }

    #[Test]
    public function itDrainsFullBatchesUntilAPartialBatch(): void
    {
        $repository = $this->createMock(RetentionRepositoryInterface::class);
        $repository->expects($this->exactly(3))->method('deleteClosedAlertsBefore')->willReturnOnConsecutiveCalls(500, 500, 12);

        $result = new DataRetentionService($repository, new MockClock(), new NullLogger(), 365, 30)->purge();

        self::assertSame(1012, $result['deletedAlerts']);
    }

    #[Test]
    public function itStopsStartingBatchesOnceItsTimeBudgetIsSpentAndReportsUnfinishedWork(): void
    {
        $elapsed = 0.0;
        $repository = $this->createMock(RetentionRepositoryInterface::class);
        // Cheap categories run first and finish; each alert batch "takes" 0.8 s.
        $repository->method('deleteRateLimitBucketsBefore')->willReturn(0);
        $repository->method('deleteFinishedInvitesBefore')->willReturn(0);
        $repository->method('deleteFinishedCompanionEnrollmentsBefore')->willReturn(0);
        $repository->method('eraseLocationOfClosedAlertsBefore')->willReturn(0);
        $repository->expects($this->exactly(3))->method('deleteClosedAlertsBefore')->willReturnCallback(
            static function () use (&$elapsed): int {
                $elapsed += 0.8;

                return 500;
            },
        );

        $service = new DataRetentionService($repository, new MockClock(), new NullLogger(), 365, 30, static function () use (&$elapsed): float {
            return $elapsed;
        });
        $result = $service->purge(2.0);

        self::assertFalse($result['completed']);
        self::assertSame(1500, $result['deletedAlerts']);
    }

    #[Test]
    public function aLargeAlertBacklogNeverStarvesTheCheapCategories(): void
    {
        $repository = $this->createMock(RetentionRepositoryInterface::class);
        $repository->expects($this->once())->method('deleteRateLimitBucketsBefore')->willReturn(3);
        $repository->expects($this->never())->method('deleteClosedAlertsBefore');
        $clockCalls = 0;
        // The budget is exhausted right after the first category.
        $service = new DataRetentionService($repository, new MockClock(), new NullLogger(), 365, 30, static function () use (&$clockCalls): float {
            return ++$clockCalls > 2 ? 10.0 : 0.0;
        });

        $result = $service->purge(1.0);

        self::assertSame(3, $result['deletedRateLimitBuckets']);
        self::assertFalse($result['completed']);
    }

    #[Test]
    public function itNeverKeepsLocationsLongerThanTheAlertsThemselves(): void
    {
        $clock = new MockClock('2026-11-21T12:00:00+00:00');
        $repository = $this->createMock(RetentionRepositoryInterface::class);
        $repository->expects($this->once())->method('eraseLocationOfClosedAlertsBefore')
            ->with(new DateTimeImmutable('2026-11-11T12:00:00+00:00'), 500);

        new DataRetentionService($repository, $clock, new NullLogger(), 10, 30)->purge();
    }

    #[Test]
    public function theCommandPrintsWhatWasPurged(): void
    {
        $repository = $this->createMock(RetentionRepositoryInterface::class);
        $repository->method('deleteClosedAlertsBefore')->willReturn(2);
        $tester = new CommandTester(new PurgeExpiredDataCommand(new DataRetentionService($repository, new MockClock(), new NullLogger(), 365, 30)));

        self::assertSame(0, $tester->execute([]));
        self::assertStringContainsString('deletedAlerts: 2', $tester->getDisplay());
    }
}
