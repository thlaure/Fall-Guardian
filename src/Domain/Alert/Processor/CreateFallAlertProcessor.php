<?php

declare(strict_types=1);

namespace App\Domain\Alert\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Request\CreateFallAlertInputDTO;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use DateTimeImmutable;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * @implements ProcessorInterface<CreateFallAlertInputDTO, FallAlertOutputDTO>
 */
final readonly class CreateFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionServiceInterface $alertIngestionService,
        private DeviceContextInterface $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        assert($data instanceof CreateFallAlertInputDTO);

        $device = $this->currentDeviceProvider->requireDevice();

        if ($device->isCaregiver()) {
            throw new AccessDeniedHttpException('Caregiver devices cannot create fall alerts.');
        }

        $alert = $this->alertIngestionService->createAlert(
            $device,
            $data->clientAlertId,
            $data->fallTimestamp ?? new DateTimeImmutable(),
            $data->locale,
            $data->latitude,
            $data->longitude,
        );

        return FallAlertOutputDTO::fromEntity($alert);
    }
}
