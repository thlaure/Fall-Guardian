<?php

declare(strict_types=1);

namespace App\Tests\Unit\Entity;

use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class FallAlertTest extends TestCase
{
    private function buildAlert(): FallAlert
    {
        $device = new Device('device-1', 'hash', 'ios', '1.0.0');

        return new FallAlert($device, 'client-001', new DateTimeImmutable(), 'en', null, null);
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
}
