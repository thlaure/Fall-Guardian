<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Api\CancelFallAlertInput;
use App\Api\FallAlertView;
use App\Application\AlertIngestionService;
use App\Security\CurrentDeviceProvider;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<CancelFallAlertInput, FallAlertView>
 */
final class CancelFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private readonly AlertIngestionService $alertIngestionService,
        private readonly CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertView
    {
        $clientAlertId = $uriVariables['clientAlertId'] ?? null;

        if (!is_string($clientAlertId) || '' === $clientAlertId) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $alert = $this->alertIngestionService->cancelAlert(
            $this->currentDeviceProvider->requireDevice(),
            $clientAlertId,
        );

        if (null === $alert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertView::fromEntity($alert);
    }
}
