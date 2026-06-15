<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Provider;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Response\LinkedProtectedPersonOutputDTO;
use App\Infrastructure\Http\Security\DeviceContextInterface;

/**
 * @implements ProviderInterface<LinkedProtectedPersonOutputDTO>
 */
final readonly class LinkedProtectedPersonsProvider implements ProviderInterface
{
    public function __construct(
        private DeviceContextInterface $currentDeviceProvider,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
    ) {
    }

    /** @return list<LinkedProtectedPersonOutputDTO> */
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): array
    {
        $caregiverDevice = $this->currentDeviceProvider->requireDevice();

        return array_map(
            LinkedProtectedPersonOutputDTO::fromLink(...),
            $this->caregiverLinkRepository->findByCaregiverDevice($caregiverDevice),
        );
    }
}
