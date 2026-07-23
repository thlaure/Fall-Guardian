<?php

declare(strict_types=1);

namespace App\Domain\Alert\Service;

use App\Domain\Alert\Message\SendFallAlertPushMessage;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use Psr\Clock\ClockInterface;
use Symfony\Component\Messenger\MessageBusInterface;

final readonly class OverdueAlertReconciler
{
    private const int STALE_DISPATCH_CLAIM_SECONDS = 60;

    public function __construct(
        private FallAlertRepositoryInterface $fallAlertRepository,
        private MessageBusInterface $messageBus,
        private ClockInterface $clock,
    ) {
    }

    public function reconcile(int $limit = 100): int
    {
        $now = $this->clock->now();
        $staleBefore = $now->modify(sprintf('-%d seconds', self::STALE_DISPATCH_CLAIM_SECONDS));
        $alertIds = $this->fallAlertRepository->findDispatchCandidateIds($now, $staleBefore, $limit);

        foreach ($alertIds as $alertId) {
            $this->messageBus->dispatch(new SendFallAlertPushMessage($alertId));
        }

        return count($alertIds);
    }
}
