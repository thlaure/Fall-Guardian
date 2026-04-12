<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Application\Caregiver\DTO\CaregiverAlertView;
use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;

/**
 * @implements ProviderInterface<CaregiverAlertView>
 */
final readonly class CaregiverAlertsProvider implements ProviderInterface
{
    public function __construct(
        private CurrentDeviceProvider $currentDeviceProvider,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private FallAlertRepositoryInterface $fallAlertRepository,
        private AlertAcknowledgementRepositoryInterface $acknowledgementRepository,
    ) {
    }

    /** @return list<CaregiverAlertView> */
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): array
    {
        $caregiverDevice = $this->currentDeviceProvider->requireDevice();

        $links = $this->caregiverLinkRepository->findByCaregiverDevice($caregiverDevice);

        if ([] === $links) {
            return [];
        }

        $result = [];

        foreach ($links as $link) {
            $alerts = $this->fallAlertRepository->findByDevice($link->getProtectedDevice());

            foreach ($alerts as $alert) {
                $ack = $this->acknowledgementRepository->findByCaregiverAndAlert($alert, $caregiverDevice);
                $result[] = CaregiverAlertView::fromEntity($alert, $ack instanceof \App\Entity\AlertAcknowledgement);
            }
        }

        return $result;
    }
}
