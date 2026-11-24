<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Handler\SendFallAlertReminderMessageHandler;
use App\Domain\Alert\Message\SendFallAlertReminderMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Port\PushAttemptRepositoryInterface;
use App\Domain\Alert\Service\CaregiverAlertNotifier;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Model\FallAlertPushPayload;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;

final class SendFallAlertReminderMessageHandlerTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $alerts;

    private PushGatewayInterface&MockObject $gateway;

    private SendFallAlertReminderMessageHandler $handler;

    protected function setUp(): void
    {
        $this->alerts = $this->createMock(FallAlertRepositoryInterface::class);
        $this->gateway = $this->createMock(PushGatewayInterface::class);
        $caregiver = new Device('caregiver', 'hash-caregiver', 'ios', '1.0.0');
        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiver);
        $links = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $links->method('findActiveByProtectedDevice')->willReturn([$link]);
        $tokens = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $tokens->method('findByDevice')->willReturn(new CaregiverPushToken($caregiver, 'token'));

        $this->handler = new SendFallAlertReminderMessageHandler(
            $this->alerts,
            new CaregiverAlertNotifier($links, $tokens, $this->createMock(PushAttemptRepositoryInterface::class), $this->gateway, new NullLogger()),
            new NullLogger(),
        );
    }

    #[Test]
    public function itRemindsCaregiversOfAnUnacknowledgedAlert(): void
    {
        $this->alerts->method('findById')->willReturn($this->alertWithStatus(FallAlertStatus::Sent));
        $this->gateway->expects($this->once())
            ->method('send')
            ->with('token', $this->callback(static fn (FallAlertPushPayload $payload): bool => $payload->reminder))
            ->willReturn(['providerMessageId' => 'id', 'status' => 'sent']);

        ($this->handler)(new SendFallAlertReminderMessage('alert-id', 1));
    }

    #[Test]
    public function itSkipsAnAlertAcknowledgedOrCancelledMeanwhile(): void
    {
        $this->alerts->method('findById')->willReturn($this->alertWithStatus(FallAlertStatus::Acknowledged));
        $this->gateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertReminderMessage('alert-id', 1));
    }

    #[Test]
    public function itIgnoresAnAlertThatNoLongerExists(): void
    {
        $this->alerts->method('findById')->willReturn(null);
        $this->gateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertReminderMessage('alert-id', 1));
    }

    private function alertWithStatus(FallAlertStatus $status): FallAlert
    {
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getStatus')->willReturn($status);
        $alert->method('getId')->willReturn(\Symfony\Component\Uid\Uuid::v7());
        $alert->method('getDevice')->willReturn(new Device('protected', 'hash-protected', 'ios', '1.0.0'));
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable('2026-07-23T08:00:00+00:00'));
        $alert->method('getCancelDeadlineAt')->willReturn(new DateTimeImmutable('2026-07-23T08:00:30+00:00'));

        return $alert;
    }
}
