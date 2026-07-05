<?php

declare(strict_types=1);

namespace App\Domain\Alert\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Request\AttachFallAlertLocationInputDTO;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Entity\FallAlert;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<AttachFallAlertLocationInputDTO, FallAlertOutputDTO>
 */
final readonly class AttachFallAlertLocationProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionServiceInterface $alertIngestionService,
        private DeviceContextInterface $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        if (!$data instanceof AttachFallAlertLocationInputDTO) {
            throw new BadRequestHttpException('Invalid fall alert location payload.');
        }

        $clientAlertId = $uriVariables['clientAlertId'] ?? null;

        if (!is_string($clientAlertId) || '' === $clientAlertId) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $device = $this->currentDeviceProvider->requireDevice();

        if ($device->isCaregiver()) {
            throw new AccessDeniedHttpException('Caregiver devices cannot update protected-person fall alerts.');
        }

        $alert = $this->alertIngestionService->attachLocation($device, $clientAlertId, $data->latitude, $data->longitude);

        if (!$alert instanceof FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertOutputDTO::fromEntity($alert);
    }
}
