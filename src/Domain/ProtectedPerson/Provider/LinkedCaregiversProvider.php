<?php

declare(strict_types=1);

namespace App\Domain\ProtectedPerson\Provider;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\ProtectedPerson\Response\LinkedCaregiverOutputDTO;
use App\Infrastructure\Http\Security\DeviceContextInterface;

/**
 * @implements ProviderInterface<LinkedCaregiverOutputDTO>
 */
final readonly class LinkedCaregiversProvider implements ProviderInterface
{
    public function __construct(
        private DeviceContextInterface $currentDeviceProvider,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
    ) {
    }

    /** @return list<LinkedCaregiverOutputDTO> */
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): array
    {
        $device = $this->currentDeviceProvider->requireDevice();
        $links = $this->caregiverLinkRepository->findActiveByProtectedDevice($device);

        return array_map(
            LinkedCaregiverOutputDTO::fromLink(...),
            $links,
        );
    }
}
