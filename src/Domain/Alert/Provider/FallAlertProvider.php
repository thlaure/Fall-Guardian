<?php

declare(strict_types=1);

namespace App\Domain\Alert\Provider;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Alert\Response\FallAlertOutputDTO;
use App\Domain\Alert\Service\AlertIngestionServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProviderInterface<FallAlertOutputDTO>
 */
final readonly class FallAlertProvider implements ProviderInterface
{
    public function __construct(
        private AlertIngestionServiceInterface $alertIngestionService,
        private DeviceContextInterface $currentDeviceProvider,
    ) {
    }

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        $alertId = $uriVariables['id'] ?? null;

        if (!is_string($alertId) || '' === $alertId) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $alert = $this->alertIngestionService->getAlertForDevice(
            $this->currentDeviceProvider->requireDevice(),
            $alertId,
        );

        if (!$alert instanceof \App\Entity\FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertOutputDTO::fromEntity($alert);
    }
}
