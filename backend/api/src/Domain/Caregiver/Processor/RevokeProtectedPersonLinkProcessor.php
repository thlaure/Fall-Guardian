<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Service\CaregiverLinkRevocationService;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/** @implements ProcessorInterface<null, null> */
final readonly class RevokeProtectedPersonLinkProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceContextInterface $deviceContext,
        private CaregiverLinkRevocationService $revocationService,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        $rawId = $uriVariables['id'] ?? '';
        $linkId = is_string($rawId) ? $rawId : '';

        if (!$this->revocationService->revokeForCaregiver($this->deviceContext->requireDevice(), $linkId)) {
            throw new NotFoundHttpException('Protected-person link not found.');
        }

        return null;
    }
}
