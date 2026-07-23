<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\OverdueAlertReconciler;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;

final class OverdueAlertReconcilerTest extends TestCase
{
    #[Test]
    public function itQueuesEveryDatabaseDispatchCandidate(): void
    {
        $clock = new MockClock('2026-07-23T08:00:31+00:00');
        $repository = $this->createMock(FallAlertRepositoryInterface::class);
        $repository->expects(self::once())
            ->method('findDispatchCandidateIds')
            ->with(
                $clock->now(),
                $clock->now()->modify('-60 seconds'),
                50,
            )
            ->willReturn(['alert-1', 'alert-2']);

        $dispatched = [];
        $bus = $this->createMock(MessageBusInterface::class);
        $bus->expects(self::exactly(2))
            ->method('dispatch')
            ->willReturnCallback(static function (object $message) use (&$dispatched): Envelope {
                $dispatched[] = $message;

                return new Envelope($message);
            });

        $reconciler = new OverdueAlertReconciler($repository, $bus, $clock);

        self::assertSame(2, $reconciler->reconcile(50));
        self::assertEquals(
            [
                new SendFallAlertPushMessage('alert-1'),
                new SendFallAlertPushMessage('alert-2'),
            ],
            $dispatched,
        );
    }
}
