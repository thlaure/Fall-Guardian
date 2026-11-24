<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Alert\Handler\SendFallAlertPushMessageHandler;
use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Port\PushAttemptRepositoryInterface;
use App\Domain\Alert\Service\CaregiverAlertNotifier;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Exception\InvalidPushTokenException;
use App\Domain\Push\Exception\PermanentPushDeliveryException;
use App\Domain\Push\Exception\TransientPushDeliveryException;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;
use App\Infrastructure\Push\FcmPushGateway;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use Symfony\Component\Clock\MockClock;

final class SendFallAlertPushMessageHandlerTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $fallAlertRepository;

    private CaregiverLinkRepositoryInterface&MockObject $linkRepository;

    private CaregiverPushTokenRepositoryInterface&MockObject $pushTokenRepository;

    private PushAttemptRepositoryInterface&MockObject $pushAttemptRepository;

    private PushGatewayInterface&MockObject $pushGateway;

    private MockClock $clock;

    private SendFallAlertPushMessageHandler $handler;

    private FallAlert $alert;

    protected function setUp(): void
    {
        $this->fallAlertRepository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->linkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->pushTokenRepository = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $this->pushAttemptRepository = $this->createMock(PushAttemptRepositoryInterface::class);
        $this->pushGateway = $this->createMock(PushGatewayInterface::class);
        $this->pushGateway->method('getProviderName')->willReturn('fake');
        $this->clock = new MockClock('2026-07-23T08:00:31+00:00');

        $this->handler = new SendFallAlertPushMessageHandler(
            $this->fallAlertRepository,
            new CaregiverAlertNotifier($this->linkRepository, $this->pushTokenRepository, $this->pushAttemptRepository, $this->pushGateway, new NullLogger()),
            $this->clock,
            new NullLogger(),
        );

        $protectedDevice = new Device('protected-device', 'hash-protected', 'ios', '1.0.0');
        $this->alert = new FallAlert($protectedDevice, 'client-1', new DateTimeImmutable('2026-07-23T08:00:00+00:00'), 'en', null, null, new DateTimeImmutable('2026-07-23T08:00:00+00:00'));
        $this->alert->claimForDispatch($this->clock->now(), $this->clock->now()->modify('-60 seconds'));
    }

    #[Test]
    public function itDoesNothingWhenTheAlertCannotBeClaimed(): void
    {
        $this->fallAlertRepository->method('claimForDispatch')->willReturn(null);
        $this->pushGateway->expects($this->never())->method('send');
        $this->fallAlertRepository->expects($this->never())->method('completeDispatch');

        ($this->handler)(new SendFallAlertPushMessage('unknown-id'));
    }

    #[Test]
    public function itClaimsWithAStaleThresholdAboveTheWorstCaseRoundDuration(): void
    {
        $this->fallAlertRepository->expects($this->once())
            ->method('claimForDispatch')
            ->with('alert-id', $this->clock->now(), $this->clock->now()->modify('-60 seconds'))
            ->willReturn(null);

        ($this->handler)(new SendFallAlertPushMessage('alert-id'));
    }

    #[Test]
    public function theStaleThresholdExceedsTheLongestGapBetweenClaimRefreshes(): void
    {
        // Worst case between two refreshes: one OAuth token fetch + one FCM send.
        self::assertLessThan(
            SendFallAlertPushMessageHandler::STALE_DISPATCH_CLAIM_SECONDS,
            2 * FcmPushGateway::HTTP_MAX_DURATION_SECONDS * 1.5,
        );
    }

    #[Test]
    public function itMarksTheAlertSentWhenEveryCaregiverWasReached(): void
    {
        $this->givenClaimedAlert();
        $this->givenCaregivers(['first' => 'token-1', 'second' => 'token-2']);
        $this->pushGateway->expects($this->exactly(2))->method('send')->willReturn(['providerMessageId' => 'push-1', 'status' => 'sent']);
        $this->pushAttemptRepository->expects($this->exactly(2))->method('save');
        $this->fallAlertRepository->expects($this->exactly(2))->method('touchDispatchClaim');

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::Sent, null)
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itSchedulesABoundedRetryAfterATransientProviderFailure(): void
    {
        $this->givenClaimedAlert();
        $this->givenCaregivers(['first' => 'token-1']);
        $this->pushGateway->method('send')->willThrowException(new TransientPushDeliveryException('FCM send failed (HTTP 503).', 'UNAVAILABLE'));
        $this->pushTokenRepository->expects($this->never())->method('deleteIfUnchanged');

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::Failed, $this->clock->now()->modify('+15 seconds'))
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itRetriesOnlyTheCaregiversNotYetReachedAsPartiallySent(): void
    {
        $this->givenClaimedAlert();
        $devices = $this->givenCaregivers(['first' => 'token-1', 'second' => 'token-2']);
        $this->pushAttemptRepository->method('findSentCaregiverDeviceIds')
            ->with($this->alert, 0)
            ->willReturn([$devices['first']->getId()->toRfc4122()]);
        $this->pushGateway->expects($this->once())
            ->method('send')
            ->with('token-2', $this->anything())
            ->willThrowException(new TransientPushDeliveryException('timeout', 'transport'));

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::PartiallySent, $this->clock->now()->modify('+15 seconds'))
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itDeletesAPermanentlyInvalidTokenAndStillRetriesWhenNobodyWasReached(): void
    {
        $this->givenClaimedAlert();
        $devices = $this->givenCaregivers(['first' => 'dead-token']);
        $this->pushGateway->method('send')->willThrowException(new InvalidPushTokenException('FCM send failed (HTTP 404).', 'UNREGISTERED'));
        $this->pushTokenRepository->expects($this->once())
            ->method('deleteIfUnchanged')
            ->with($devices['first'], 'dead-token')
            ->willReturn(true);

        // Nobody reached: a caregiver may re-register a token within the retry window.
        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::Failed, $this->clock->now()->modify('+15 seconds'))
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itKeepsTheTokenAndDoesNotRetryWhenTheProviderRejectsTheMessage(): void
    {
        $this->givenClaimedAlert();
        $this->givenCaregivers(['first' => 'token-1', 'second' => 'token-2']);
        // e.g. INVALID_ARGUMENT on the payload: every caregiver gets the same rejection.
        $this->pushGateway->method('send')->willThrowException(new PermanentPushDeliveryException('FCM send failed (HTTP 400).', 'INVALID_ARGUMENT'));
        $this->pushTokenRepository->expects($this->never())->method('deleteIfUnchanged');

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::Failed, null)
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itFinalisesAsPartiallySentWhenTheOtherCaregiverMessageWasRejected(): void
    {
        $this->givenClaimedAlert();
        $this->givenCaregivers(['first' => 'token-1', 'second' => 'token-2']);
        $this->pushGateway->method('send')->willReturnCallback(
            static fn (string $token): array => 'token-2' === $token
                ? throw new PermanentPushDeliveryException('FCM send failed (HTTP 403).', 'SENDER_ID_MISMATCH')
                : ['providerMessageId' => 'push-1', 'status' => 'sent'],
        );
        $this->pushTokenRepository->expects($this->never())->method('deleteIfUnchanged');

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::PartiallySent, null)
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itFinalisesAsPartiallySentWhenTheOnlyFailureIsADeadToken(): void
    {
        $this->givenClaimedAlert();
        $this->givenCaregivers(['first' => 'token-1', 'second' => 'dead-token']);
        $this->pushGateway->method('send')->willReturnCallback(
            static fn (string $token): array => 'dead-token' === $token
                ? throw new InvalidPushTokenException('FCM send failed (HTTP 400).', 'INVALID_ARGUMENT')
                : ['providerMessageId' => 'push-1', 'status' => 'sent'],
        );

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::PartiallySent, null)
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itRetriesWhenNoCaregiverIsLinkedYet(): void
    {
        $this->givenClaimedAlert();
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([]);
        $this->pushGateway->expects($this->never())->method('send');

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::Failed, $this->clock->now()->modify('+15 seconds'))
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itStopsRetryingOnceTheAttemptBudgetIsExhausted(): void
    {
        for ($attempt = 1; $attempt < FallAlert::MAX_DISPATCH_ATTEMPTS; ++$attempt) {
            $this->alert->claimForDispatch($this->clock->now()->modify('+1 hour'), $this->clock->now()->modify('+1 hour'));
        }
        self::assertFalse($this->alert->hasDispatchAttemptsLeft());

        $this->givenClaimedAlert();
        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn([]);

        $this->fallAlertRepository->expects($this->once())
            ->method('completeDispatch')
            ->with($this->alertId(), FallAlertStatus::Failed, null)
            ->willReturn(true);

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itDoesNotFailWhenTheOutcomeWasSupersededByAConcurrentAcknowledgement(): void
    {
        $this->givenClaimedAlert();
        $this->givenCaregivers(['first' => 'token-1']);
        $this->pushGateway->method('send')->willReturn(['providerMessageId' => 'push-1', 'status' => 'sent']);

        // The repository refuses the update because the alert left `dispatching`.
        $this->fallAlertRepository->expects($this->once())->method('completeDispatch')->willReturn(false);
        $this->fallAlertRepository->expects($this->never())->method('save');

        ($this->handler)(new SendFallAlertPushMessage($this->alertId()));
    }

    #[Test]
    public function itComputesIncreasingBoundedBackoff(): void
    {
        self::assertSame(15, FallAlert::retryBackoffSeconds(1));
        self::assertSame(30, FallAlert::retryBackoffSeconds(2));
        self::assertSame(240, FallAlert::retryBackoffSeconds(5));
        self::assertSame(240, FallAlert::retryBackoffSeconds(50));
        self::assertSame(15, FallAlert::retryBackoffSeconds(0));
    }

    private function givenClaimedAlert(): void
    {
        $this->fallAlertRepository->method('claimForDispatch')->willReturn($this->alert);
    }

    /**
     * @param array<string, string> $tokensByName
     *
     * @return array<string, Device>
     */
    private function givenCaregivers(array $tokensByName): array
    {
        $links = [];
        $devices = [];
        $tokens = [];

        foreach ($tokensByName as $name => $token) {
            $device = new Device('caregiver-'.$name, 'hash-'.$name, 'android', '1.0.0');
            $devices[$name] = $device;
            $link = $this->createMock(CaregiverLink::class);
            $link->method('getCaregiverDevice')->willReturn($device);
            $link->method('getProtectedPersonName')->willReturn('Mamie');
            $links[] = $link;
            $tokens[] = [$device, new CaregiverPushToken($device, $token)];
        }

        $this->linkRepository->method('findActiveByProtectedDevice')->willReturn($links);
        $this->pushTokenRepository->method('findByDevice')->willReturnCallback(
            static function (Device $device) use ($tokens): ?CaregiverPushToken {
                foreach ($tokens as [$candidate, $token]) {
                    if ($candidate === $device) {
                        return $token;
                    }
                }

                return null;
            },
        );

        return $devices;
    }

    private function alertId(): string
    {
        return $this->alert->getId()->toRfc4122();
    }
}
