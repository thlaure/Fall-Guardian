<?php

declare(strict_types=1);

namespace App\Domain\Device\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Device\Request\RevokeDeviceInputDTO;
use App\Domain\Device\Service\DeviceRevocationService;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;

/** @implements ProcessorInterface<RevokeDeviceInputDTO, void> */
final readonly class RevokeDeviceProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceContextInterface $deviceContext,
        private DeviceRevocationService $deviceRevocationService,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        if (!$data instanceof RevokeDeviceInputDTO || !isset($uriVariables['deviceId']) || !is_string($uriVariables['deviceId'])) {
            throw new BadRequestHttpException('Invalid device revocation request.');
        }

        $this->deviceRevocationService->revoke($this->deviceContext->requireDevice(), $uriVariables['deviceId']);
    }
}
