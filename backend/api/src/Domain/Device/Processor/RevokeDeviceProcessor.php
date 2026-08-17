<?php

declare(strict_types=1);

namespace App\Domain\Device\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Device\Request\RevokeDeviceInputDTO;
use App\Domain\Device\Service\DeviceRevocationService;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/** @implements ProcessorInterface<RevokeDeviceInputDTO, void> */
final readonly class RevokeDeviceProcessor implements ProcessorInterface
{
    private const string NOT_FOUND_MESSAGE = 'Device not found.';

    public function __construct(
        private DeviceContextInterface $deviceContext,
        private DeviceRevocationService $deviceRevocationService,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        if (!$data instanceof RevokeDeviceInputDTO || !isset($uriVariables['deviceId']) || !is_string($uriVariables['deviceId'])) {
            throw new BadRequestHttpException('Invalid device revocation request.');
        }

        $requestingDevice = $this->deviceContext->requireDevice();
        $this->rateLimiter->consume('device_revoke', 10, 600, $requestingDevice->getPublicId());

        try {
            $this->deviceRevocationService->revoke($requestingDevice, $uriVariables['deviceId']);
        } catch (DomainException $e) {
            if (self::NOT_FOUND_MESSAGE === $e->getMessage()) {
                throw new NotFoundHttpException($e->getMessage(), $e);
            }

            throw new AccessDeniedHttpException($e->getMessage(), $e);
        }
    }
}
