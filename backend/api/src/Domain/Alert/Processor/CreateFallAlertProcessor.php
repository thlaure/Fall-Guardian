<?php

declare(strict_types=1);

namespace App\Domain\Alert\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Request\CreateFallAlertInputDTO;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Enum\FallAlertStatus;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DateTimeImmutable;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

/**
 * @implements ProcessorInterface<CreateFallAlertInputDTO, FallAlertOutputDTO>
 */
final readonly class CreateFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionServiceInterface $alertIngestionService,
        private DeviceContextInterface $currentDeviceProvider,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        if (!$data instanceof CreateFallAlertInputDTO) {
            throw new BadRequestHttpException('Invalid fall alert payload.');
        }

        $device = $this->currentDeviceProvider->requireDevice();

        if ($device->isCaregiver()) {
            throw new AccessDeniedHttpException('Caregiver devices cannot create fall alerts.');
        }

        $this->rateLimiter->consume('fall_alert_create', 6, 60, $device->getPublicId());

        $fallTimestamp = $data->fallTimestamp ?? new DateTimeImmutable();
        $alert = $data->cancelled
            ? $this->alertIngestionService->createCancelledAlert(
                $device,
                $data->clientAlertId,
                $fallTimestamp,
                $data->locale,
                $data->latitude,
                $data->longitude,
            )
            : $this->alertIngestionService->createAlert(
                $device,
                $data->clientAlertId,
                $fallTimestamp,
                $data->locale,
                $data->latitude,
                $data->longitude,
            );

        if ($data->cancelled && FallAlertStatus::Cancelled !== $alert->getStatus()) {
            throw new ConflictHttpException('The cancellation deadline has passed or alert dispatch has started.');
        }

        return FallAlertOutputDTO::fromEntity($alert);
    }
}
