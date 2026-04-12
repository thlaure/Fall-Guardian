<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Application\Alert\DTO\FallAlertView;
use App\Application\Alert\Handler\AlertIngestionService;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;

use function is_string;

use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProviderInterface<FallAlertView>
 */
final readonly class FallAlertProvider implements ProviderInterface
{
    public function __construct(
        private AlertIngestionService $alertIngestionService,
        private CurrentDeviceProvider $currentDeviceProvider,
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

        if (!$alert instanceof \App\Entity\FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertView::fromEntity($alert);
    }
}
