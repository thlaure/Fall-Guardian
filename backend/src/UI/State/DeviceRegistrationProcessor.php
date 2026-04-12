<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Device\DTO\DeviceRegistrationInput;
use App\Application\Device\DTO\DeviceRegistrationOutput;
use App\Application\Device\Handler\DeviceRegistrationService;
use App\Enum\DeviceType;

use function assert;

/**
 * @implements ProcessorInterface<DeviceRegistrationInput, DeviceRegistrationOutput>
 */
final readonly class DeviceRegistrationProcessor implements ProcessorInterface
{
    public function __construct(private DeviceRegistrationService $deviceRegistrationService)
    {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): DeviceRegistrationOutput
    {
        assert($data instanceof DeviceRegistrationInput);

        $credentials = $this->deviceRegistrationService->register(
            $data->platform,
            $data->appVersion,
            DeviceType::from($data->deviceType),
        );

        return new DeviceRegistrationOutput($credentials['deviceId'], $credentials['deviceToken']);
    }
}
