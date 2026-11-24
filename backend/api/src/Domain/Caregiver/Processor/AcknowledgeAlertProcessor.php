<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Request\AcknowledgeAlertInputDTO;
use App\Entity\AlertAcknowledgement;
use App\Entity\FallAlert;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<AcknowledgeAlertInputDTO, null>
 */
final readonly class AcknowledgeAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceContextInterface $currentDeviceProvider,
        private FallAlertRepositoryInterface $fallAlertRepository,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private AlertAcknowledgementRepositoryInterface $acknowledgementRepository,
        private EndpointRateLimiterInterface $rateLimiter,
        private ClockInterface $clock,
        private LoggerInterface $logger,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        $rawId = $uriVariables['id'] ?? '';
        $alertId = is_string($rawId) ? $rawId : '';

        $alert = $this->fallAlertRepository->findById($alertId);

        if (!$alert instanceof FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $caregiverDevice = $this->currentDeviceProvider->requireDevice();

        $this->rateLimiter->consume('acknowledge_alert', 20, 60, $caregiverDevice->getPublicId());

        $links = $this->caregiverLinkRepository->findActiveByProtectedDevice($alert->getDevice());
        $isLinked = array_any($links, static fn ($link) => $link->getCaregiverDevice()->getId()->equals($caregiverDevice->getId()));

        if (!$isLinked) {
            // Same response as an unknown alert: never reveal that an alert
            // exists to a caregiver who is not linked to its protected person.
            throw new NotFoundHttpException('Alert not found.');
        }

        $existing = $this->acknowledgementRepository->findByCaregiverAndAlert($alert, $caregiverDevice);

        if (!$existing instanceof AlertAcknowledgement) {
            $previousStatus = $alert->getStatus();
            $alert->markAcknowledged();
            $ack = new AlertAcknowledgement($alert, $caregiverDevice, $this->clock->now());
            $this->acknowledgementRepository->save($ack);
            $this->logger->info('alert.acknowledged', [
                'alertId' => $alert->getId()->toRfc4122(),
                'caregiverDeviceId' => $caregiverDevice->getPublicId(),
                'previousStatus' => $previousStatus->value,
                'status' => $alert->getStatus()->value,
            ]);
        }

        return null;
    }
}
