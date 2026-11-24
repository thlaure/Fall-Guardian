<?php

declare(strict_types=1);

namespace App\Domain\Alert\Handler;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Service\CaregiverAlertNotifier;
use App\Domain\Alert\Service\NotificationRoundResult;
use App\Entity\FallAlert;
use App\Enum\FallAlertStatus;

use const DATE_ATOM;

use DateTimeImmutable;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

/**
 * Runs one dispatch round for a fall alert: the initial caregiver push once the
 * grace period expired, the resumption of an interrupted round, or a retry of
 * a failed/partially-sent round.
 */
#[AsMessageHandler]
final readonly class SendFallAlertPushMessageHandler
{
    /**
     * A claim older than this is considered abandoned by a crashed worker.
     * The claim is refreshed after every provider call (each bounded to 15 s,
     * plus up to 15 s for the OAuth token), so a live round never gets close.
     */
    public const int STALE_DISPATCH_CLAIM_SECONDS = 120;

    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private CaregiverAlertNotifier $notifier,
        private ClockInterface $clock,
        private LoggerInterface $logger,
    ) {
    }

    public function __invoke(SendFallAlertPushMessage $message): void
    {
        $now = $this->clock->now();
        $alert = $this->fallAlertRepository->claimForDispatch(
            $message->fallAlertId,
            $now,
            $now->modify(sprintf('-%d seconds', self::STALE_DISPATCH_CLAIM_SECONDS)),
        );

        if (!$alert instanceof FallAlert) {
            return;
        }

        $alertId = $alert->getId()->toRfc4122();
        $this->logger->info('alert.dispatch_claimed', [
            'alertId' => $alertId,
            'status' => FallAlertStatus::Dispatching->value,
            'attempt' => $alert->getDispatchAttempts(),
        ]);

        $result = $this->notifier->notify(
            $alert,
            0,
            fn () => $this->fallAlertRepository->touchDispatchClaim($alertId, $this->clock->now()),
        );

        if (0 === $result->delivered()) {
            $this->logger->warning('alert.no_caregiver_reached', [
                'alertId' => $alertId,
                'attempt' => $alert->getDispatchAttempts(),
                ...$result->toLogContext(),
            ]);
        }

        [$status, $retryable] = $this->outcome($result);
        $nextRetryAt = $retryable && $alert->hasDispatchAttemptsLeft()
            ? $this->nextRetryAt($alert)
            : null;

        $applied = $this->fallAlertRepository->completeDispatch($alertId, $status, $nextRetryAt);

        if (!$applied) {
            $this->logger->info('alert.dispatch_outcome_superseded', [
                'alertId' => $alertId,
                'outcome' => $status->value,
                ...$result->toLogContext(),
            ]);

            return;
        }

        $this->logger->info('alert.dispatch_completed', [
            'alertId' => $alertId,
            'status' => $status->value,
            'attempt' => $alert->getDispatchAttempts(),
            'nextRetryAt' => $nextRetryAt?->format(DATE_ATOM),
            ...$result->toLogContext(),
        ]);

        if ($retryable && null === $nextRetryAt) {
            $this->logger->error('alert.dispatch_retries_exhausted', [
                'alertId' => $alertId,
                'status' => $status->value,
                'attempts' => $alert->getDispatchAttempts(),
            ]);
        }
    }

    /**
     * @return array{0: FallAlertStatus, 1: bool} final status and whether another round may help
     */
    private function outcome(NotificationRoundResult $result): array
    {
        if (0 === $result->delivered()) {
            // Nobody reached: transient provider failure, dead tokens, or no
            // linked caregiver/token yet. A caregiver may (re-)register within
            // the retry window, so keep retrying until attempts run out.
            return [FallAlertStatus::Failed, true];
        }

        if (0 === $result->transientFailures && 0 === $result->invalidTokens) {
            return [FallAlertStatus::Sent, false];
        }

        return [FallAlertStatus::PartiallySent, $result->transientFailures > 0];
    }

    private function nextRetryAt(FallAlert $alert): DateTimeImmutable
    {
        return $this->clock->now()->modify(sprintf('+%d seconds', FallAlert::retryBackoffSeconds($alert->getDispatchAttempts())));
    }
}
