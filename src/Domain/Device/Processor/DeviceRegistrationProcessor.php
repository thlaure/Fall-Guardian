<?php

declare(strict_types=1);

namespace App\Domain\Device\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Device\Request\DeviceRegistrationInputDTO;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Domain\Device\Service\DeviceRegistrationService;
use App\Enum\DeviceType;

use function assert;

/**
 * @implements ProcessorInterface<DeviceRegistrationInputDTO, DeviceRegistrationOutputDTO>
 */
final readonly class DeviceRegistrationProcessor implements ProcessorInterface
{
    public function __construct(private DeviceRegistrationService $deviceRegistrationService)
    {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): DeviceRegistrationOutputDTO
    {
        assert($data instanceof DeviceRegistrationInputDTO);

        return $this->deviceRegistrationService->register(
            $data->platform,
            $data->appVersion,
            DeviceType::from($data->deviceType),
        );
    }
}
