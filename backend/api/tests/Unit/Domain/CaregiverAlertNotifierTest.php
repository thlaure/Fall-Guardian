<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

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
use App\Entity\PushAttempt;
use App\Enum\PushAttemptStatus;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use RuntimeException;

final class CaregiverAlertNotifierTest extends TestCase
{
    #[Test]
    public function itSendsEachCaregiverItsOwnNameForTheProtectedPersonAndPersistsEveryAttempt(): void
    {
        $alert = $this->alert(48.8, 2.3);
        $anna = new Device('caregiver-anna', 'hash-anna', 'ios', '1.0.0');
        $bob = new Device('caregiver-bob', 'hash-bob', 'android', '1.0.0');
        $noToken = new Device('caregiver-without-token', 'hash-none', 'android', '1.0.0');

        $links = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $links->method('findActiveByProtectedDevice')->willReturn([
            $this->link($anna, 'Maman'),
            $this->link($bob, null),
            $this->link($anna, 'Duplicate link for the same device'),
            $this->link($noToken, 'Mamie'),
        ]);
        $tokens = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $tokens->method('findByDevice')->willReturnCallback(static fn (Device $device): ?CaregiverPushToken => match ($device) {
            $anna => new CaregiverPushToken($anna, 'token-anna'),
            $bob => new CaregiverPushToken($bob, 'token-bob'),
            default => null,
        });

        $saved = [];
        $attempts = $this->createMock(PushAttemptRepositoryInterface::class);
        $attempts->method('findSentCaregiverDeviceIds')->willReturn([]);
        $attempts->method('save')->willReturnCallback(static function (PushAttempt $attempt) use (&$saved): void {
            $saved[] = $attempt;
        });

        $payloads = [];
        $gateway = $this->createMock(PushGatewayInterface::class);
        $gateway->method('getProviderName')->willReturn('fake');
        $gateway->method('send')->willReturnCallback(static function (string $token, FallAlertPushPayload $payload) use (&$payloads): array {
            $payloads[$token] = $payload->toData();

            return ['providerMessageId' => 'id-'.$token, 'status' => 'sent'];
        });

        $afterEach = 0;
        $result = new CaregiverAlertNotifier($links, $tokens, $attempts, $gateway, new NullLogger())
            ->notify($alert, 0, static function () use (&$afterEach): void {
                ++$afterEach;
            });

        self::assertSame(3, $result->linkedCaregivers);
        self::assertSame(2, $result->sent);
        self::assertSame(1, $result->missingTokens);
        self::assertSame(2, $afterEach);
        self::assertCount(2, $saved);
        self::assertSame(PushAttemptStatus::Sent, $saved[0]->getStatus());
        self::assertSame(0, $saved[0]->getReminderNumber());

        self::assertSame([
            'type' => 'fall_alert',
            'alertId' => $alert->getId()->toRfc4122(),
            'fallTimestamp' => '2026-07-23T07:59:58+00:00',
            'cancelDeadlineAt' => '2026-07-23T08:00:30+00:00',
            'reminder' => '0',
            'latitude' => '48.8',
            'longitude' => '2.3',
            'protectedPersonName' => 'Maman',
        ], $payloads['token-anna']);
        self::assertArrayNotHasKey('protectedPersonName', $payloads['token-bob']);
    }

    #[Test]
    public function itSkipsCaregiversAlreadyReachedInThisRoundAndFlagsReminders(): void
    {
        $alert = $this->alert(null, null);
        $anna = new Device('caregiver-anna', 'hash-anna', 'ios', '1.0.0');
        $bob = new Device('caregiver-bob', 'hash-bob', 'android', '1.0.0');

        $links = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $links->method('findActiveByProtectedDevice')->willReturn([$this->link($anna, null), $this->link($bob, null)]);
        $tokens = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $tokens->method('findByDevice')->willReturnCallback(static fn (Device $device): CaregiverPushToken => new CaregiverPushToken($device, 'token-'.$device->getPublicId()));
        $attempts = $this->createMock(PushAttemptRepositoryInterface::class);
        $attempts->expects($this->once())
            ->method('findSentCaregiverDeviceIds')
            ->with($alert, 2)
            ->willReturn([$anna->getId()->toRfc4122()]);

        $gateway = $this->createMock(PushGatewayInterface::class);
        $gateway->expects($this->once())
            ->method('send')
            ->with('token-caregiver-bob', $this->callback(static fn (FallAlertPushPayload $payload): bool => '1' === $payload->toData()['reminder']))
            ->willReturn(['providerMessageId' => 'id', 'status' => 'sent']);

        $result = new CaregiverAlertNotifier($links, $tokens, $attempts, $gateway, new NullLogger())->notify($alert, 2);

        self::assertSame(1, $result->alreadySent);
        self::assertSame(1, $result->sent);
        self::assertSame(2, $result->delivered());
    }

    #[Test]
    public function itTreatsUnexpectedGatewayErrorsAsTransientWithoutLeakingTheirMessage(): void
    {
        $alert = $this->alert(null, null);
        $anna = new Device('caregiver-anna', 'hash-anna', 'ios', '1.0.0');
        $links = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $links->method('findActiveByProtectedDevice')->willReturn([$this->link($anna, null)]);
        $tokens = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $tokens->method('findByDevice')->willReturn(new CaregiverPushToken($anna, 'token-anna'));
        $tokens->expects($this->never())->method('deleteIfUnchanged');

        $saved = null;
        $attempts = $this->createMock(PushAttemptRepositoryInterface::class);
        $attempts->method('save')->willReturnCallback(static function (PushAttempt $attempt) use (&$saved): void {
            $saved = $attempt;
        });
        $gateway = $this->createMock(PushGatewayInterface::class);
        $gateway->method('send')->willThrowException(new RuntimeException('raw provider body with token-anna'));

        $result = new CaregiverAlertNotifier($links, $tokens, $attempts, $gateway, new NullLogger())->notify($alert, 0);

        self::assertSame(1, $result->transientFailures);
        self::assertInstanceOf(PushAttempt::class, $saved);
        self::assertSame(PushAttemptStatus::Failed, $saved->getStatus());
    }

    private function alert(?float $latitude, ?float $longitude): FallAlert
    {
        return new FallAlert(
            new Device('protected', 'hash-protected', 'ios', '1.0.0'),
            'client-1',
            new DateTimeImmutable('2026-07-23T07:59:58+00:00'),
            'fr',
            $latitude,
            $longitude,
            new DateTimeImmutable('2026-07-23T08:00:00+00:00'),
        );
    }

    private function link(Device $caregiver, ?string $protectedPersonName): CaregiverLink
    {
        $link = $this->createMock(CaregiverLink::class);
        $link->method('getCaregiverDevice')->willReturn($caregiver);
        $link->method('getProtectedPersonName')->willReturn($protectedPersonName);

        return $link;
    }
}
