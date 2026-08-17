<?php

declare(strict_types=1);

namespace App\Domain\ProtectedPerson\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Service\CaregiverLinkRevocationService;
use App\Domain\ProtectedPerson\Request\RevokeCaregiverLinkInputDTO;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use RuntimeException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/** @implements ProcessorInterface<RevokeCaregiverLinkInputDTO, void> */
final readonly class RevokeCaregiverLinkProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceContextInterface $deviceContext,
        private CaregiverLinkRevocationService $caregiverLinkRevocationService,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        if (!$data instanceof RevokeCaregiverLinkInputDTO || !isset($uriVariables['linkId']) || !is_string($uriVariables['linkId'])) {
            throw new BadRequestHttpException('Invalid caregiver link revocation request.');
        }

        $device = $this->deviceContext->requireDevice();

        $this->rateLimiter->consume('caregiver_link_revoke', 10, 600, $device->getPublicId());

        try {
            $this->caregiverLinkRevocationService->revoke($device, $uriVariables['linkId']);
        } catch (RuntimeException $e) {
            throw new NotFoundHttpException($e->getMessage(), $e);
        }
    }
}
