<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Request\ReportAlertReceiptInputDTO;
use App\Entity\FallAlert;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use Psr\Clock\ClockInterface;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<ReportAlertReceiptInputDTO, null>
 */
final readonly class ReportAlertReceiptProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceContextInterface $currentDeviceProvider,
        private FallAlertRepositoryInterface $fallAlertRepository,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private EndpointRateLimiterInterface $rateLimiter,
        private ClockInterface $clock,
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
        $this->rateLimiter->consume('report_alert_receipt', 120, 60, $caregiverDevice->getPublicId());

        $links = $this->caregiverLinkRepository->findActiveByProtectedDevice($alert->getDevice());
        $isLinked = array_any(
            $links,
            static fn ($link): bool => $link->getCaregiverDevice()->getId()->equals($caregiverDevice->getId()),
        );

        if (!$isLinked) {
            throw new AccessDeniedHttpException('You are not linked to this protected person.');
        }

        $alert->markDeliveryReceived($this->clock->now());
        $this->fallAlertRepository->save($alert);

        return null;
    }
}
