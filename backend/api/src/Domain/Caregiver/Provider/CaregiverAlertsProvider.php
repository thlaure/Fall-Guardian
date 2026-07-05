<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Provider;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Response\CaregiverAlertOutputDTO;
use App\Infrastructure\Http\Security\DeviceContextInterface;

/**
 * @implements ProviderInterface<CaregiverAlertOutputDTO>
 */
final readonly class CaregiverAlertsProvider implements ProviderInterface
{
    public function __construct(
        private DeviceContextInterface $currentDeviceProvider,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private FallAlertRepositoryInterface $fallAlertRepository,
        private AlertAcknowledgementRepositoryInterface $acknowledgementRepository,
    ) {
    }

    /** @return list<CaregiverAlertOutputDTO> */
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
                $result[] = CaregiverAlertOutputDTO::fromEntity(
                    $alert,
                    $ack instanceof \App\Entity\AlertAcknowledgement,
                    $link->getProtectedPersonName(),
                );
            }
        }

        return $result;
    }
}
