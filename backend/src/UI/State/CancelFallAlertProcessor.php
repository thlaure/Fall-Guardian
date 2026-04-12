<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Alert\DTO\CancelFallAlertInput;
use App\Application\Alert\DTO\FallAlertView;
use App\Application\Alert\Handler\AlertIngestionService;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;

use function is_string;

use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<CancelFallAlertInput, FallAlertView>
 */
final readonly class CancelFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionService $alertIngestionService,
        private CurrentDeviceProvider $currentDeviceProvider,
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

        if (!$alert instanceof \App\Entity\FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertView::fromEntity($alert);
    }
}
