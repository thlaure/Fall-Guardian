<?php

declare(strict_types=1);

namespace App\Domain\Device\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Device\Request\DeviceRegistrationInputDTO;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Domain\Device\Service\DeviceRegistrationService;
use App\Enum\DeviceType;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;

/**
 * @implements ProcessorInterface<DeviceRegistrationInputDTO, DeviceRegistrationOutputDTO>
 */
final readonly class DeviceRegistrationProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceRegistrationService $deviceRegistrationService,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): DeviceRegistrationOutputDTO
    {
        if (!$data instanceof DeviceRegistrationInputDTO) {
            throw new BadRequestHttpException('Invalid device registration payload.');
        }

        $this->rateLimiter->consume('device_registration', 20, 60);

        return $this->deviceRegistrationService->register(
            $data->platform,
            $data->appVersion,
            DeviceType::from($data->deviceType),
        );
    }
}
