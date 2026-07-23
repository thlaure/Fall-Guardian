<?php

declare(strict_types=1);

namespace App\Tests\Unit\Entity;

use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;

use const DATE_ATOM;

use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class FallAlertTest extends TestCase
{
    private function buildAlert(?DateTimeImmutable $receivedAt = null): FallAlert
    {
        $device = new Device('device-1', 'hash', 'ios', '1.0.0');

        return new FallAlert(
            $device,
            'client-001',
            new DateTimeImmutable('2026-07-23T07:00:00+00:00'),
            'en',
            null,
            null,
            $receivedAt,
        );
    }

    #[Test]
    public function itCancelsAReceivedAlert(): void
    {
        $alert = $this->buildAlert();

        $alert->cancel();

        self::assertSame(FallAlertStatus::Cancelled, $alert->getStatus());
        self::assertInstanceOf(DateTimeImmutable::class, $alert->getCancelledAt());
    }

    #[Test]
    public function itAcknowledgesAReceivedAlert(): void
    {
        $alert = $this->buildAlert();

        $alert->markAcknowledged();

        self::assertSame(FallAlertStatus::Acknowledged, $alert->getStatus());
    }

    #[Test]
    public function cancelDoesNotOverwriteAnAlreadyAcknowledgedAlert(): void
    {
        $alert = $this->buildAlert();
        $alert->markAcknowledged();

        $alert->cancel();

        self::assertSame(FallAlertStatus::Acknowledged, $alert->getStatus());
        self::assertNull($alert->getCancelledAt());
    }

    #[Test]
    public function acknowledgeDoesNotOverwriteAnAlreadyCancelledAlert(): void
    {
        $alert = $this->buildAlert();
        $alert->cancel();

        $alert->markAcknowledged();

        self::assertSame(FallAlertStatus::Cancelled, $alert->getStatus());
        self::assertInstanceOf(DateTimeImmutable::class, $alert->getCancelledAt());
    }

    #[Test]
    public function backendReceiptTimeDefinesTheCancellationDeadline(): void
    {
        $receivedAt = new DateTimeImmutable('2026-07-23T08:00:00+00:00');
        $alert = $this->buildAlert($receivedAt);

        self::assertSame($receivedAt, $alert->getReceivedAt());
        self::assertSame(
            '2026-07-23T08:00:30+00:00',
            $alert->getCancelDeadlineAt()->format(DATE_ATOM),
        );
    }

    #[Test]
    public function itRejectsCancellationAtOrAfterTheBackendDeadline(): void
    {
        $receivedAt = new DateTimeImmutable('2026-07-23T08:00:00+00:00');
        $alert = $this->buildAlert($receivedAt);

        self::assertFalse($alert->cancel($receivedAt->modify('+30 seconds')));
        self::assertSame(FallAlertStatus::Received, $alert->getStatus());
        self::assertNull($alert->getCancelledAt());
    }

    #[Test]
    public function itClaimsOnlyDueAlertsAndCreatesReceiptAndAcknowledgementDeadlines(): void
    {
        $receivedAt = new DateTimeImmutable('2026-07-23T08:00:00+00:00');
        $alert = $this->buildAlert($receivedAt);

        self::assertFalse(
            $alert->claimForDispatch(
                $receivedAt->modify('+29 seconds'),
                $receivedAt->modify('-1 minute'),
            ),
        );

        $claimedAt = $receivedAt->modify('+30 seconds');
        self::assertTrue(
            $alert->claimForDispatch($claimedAt, $receivedAt->modify('-1 minute')),
        );
        self::assertSame(FallAlertStatus::Dispatching, $alert->getStatus());
        self::assertSame($claimedAt, $alert->getDispatchClaimedAt());
        self::assertSame(
            '2026-07-23T08:00:45+00:00',
            $alert->getDeliveryReceiptDeadlineAt()?->format(DATE_ATOM),
        );
        self::assertSame(
            '2026-07-23T08:01:30+00:00',
            $alert->getAcknowledgementDeadlineAt()?->format(DATE_ATOM),
        );
        self::assertFalse($alert->cancel($claimedAt));
    }

    #[Test]
    public function itAllowsAStaleDispatchClaimToBeRecovered(): void
    {
        $receivedAt = new DateTimeImmutable('2026-07-23T08:00:00+00:00');
        $alert = $this->buildAlert($receivedAt);
        $firstClaim = $receivedAt->modify('+30 seconds');
        self::assertTrue($alert->claimForDispatch($firstClaim, $receivedAt));

        self::assertFalse(
            $alert->claimForDispatch(
                $firstClaim->modify('+30 seconds'),
                $firstClaim->modify('-1 second'),
            ),
        );
        self::assertTrue(
            $alert->claimForDispatch(
                $firstClaim->modify('+61 seconds'),
                $firstClaim->modify('+1 second'),
            ),
        );
    }

    #[Test]
    public function deliveryReceiptKeepsTheFirstBackendTimestamp(): void
    {
        $alert = $this->buildAlert();
        $first = new DateTimeImmutable('2026-07-23T08:00:35+00:00');
        $alert->markDeliveryReceived($first);
        $alert->markDeliveryReceived($first->modify('+5 seconds'));

        self::assertSame($first, $alert->getFirstDeliveryReceiptAt());
    }
}
