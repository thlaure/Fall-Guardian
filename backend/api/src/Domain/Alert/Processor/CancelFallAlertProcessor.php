<?php

declare(strict_types=1);

namespace App\Domain\Alert\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Request\CancelFallAlertInputDTO;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<CancelFallAlertInputDTO, FallAlertOutputDTO>
 */
final readonly class CancelFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionServiceInterface $alertIngestionService,
        private DeviceContextInterface $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        $clientAlertId = $uriVariables['clientAlertId'] ?? null;

        if (!is_string($clientAlertId) || '' === $clientAlertId) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $device = $this->currentDeviceProvider->requireDevice();

        if ($device->isCaregiver()) {
            throw new AccessDeniedHttpException('Caregiver devices cannot cancel protected-person fall alerts.');
        }

        $alert = $this->alertIngestionService->cancelAlert($device, $clientAlertId);

        if (!$alert instanceof \App\Entity\FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertOutputDTO::fromEntity($alert);
    }
}
