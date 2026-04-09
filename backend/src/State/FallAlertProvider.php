<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Api\FallAlertView;
use App\Application\AlertIngestionService;
use App\Security\CurrentDeviceProvider;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProviderInterface<FallAlertView>
 */
final class FallAlertProvider implements ProviderInterface
{
    public function __construct(
        private readonly AlertIngestionService $alertIngestionService,
        private readonly CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): FallAlertView
    {
        $alertId = $uriVariables['id'] ?? null;

        if (!is_string($alertId) || '' === $alertId) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $alert = $this->alertIngestionService->getAlertForDevice(
            $this->currentDeviceProvider->requireDevice(),
            $alertId,
        );

        if (null === $alert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertView::fromEntity($alert);
    }
}
