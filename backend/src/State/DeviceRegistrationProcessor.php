<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Api\DeviceRegistrationInput;
use App\Application\DeviceRegistrationService;
use App\Dto\DeviceRegistrationOutput;

use function assert;

/**
 * @implements ProcessorInterface<DeviceRegistrationInput, DeviceRegistrationOutput>
 */
final class DeviceRegistrationProcessor implements ProcessorInterface
{
    public function __construct(private readonly DeviceRegistrationService $deviceRegistrationService)
    {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): DeviceRegistrationOutput
    {
        assert($data instanceof DeviceRegistrationInput);

        $credentials = $this->deviceRegistrationService->register($data->platform, $data->appVersion);

        return new DeviceRegistrationOutput($credentials['deviceId'], $credentials['deviceToken']);
    }
}
