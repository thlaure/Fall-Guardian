<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Api\CreateFallAlertInput;
use App\Api\FallAlertView;
use App\Application\AlertIngestionService;
use App\Security\CurrentDeviceProvider;

use function assert;

use DateTimeImmutable;

/**
 * @implements ProcessorInterface<CreateFallAlertInput, FallAlertView>
 */
final class CreateFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private readonly AlertIngestionService $alertIngestionService,
        private readonly CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertView
    {
        assert($data instanceof CreateFallAlertInput);

        $alert = $this->alertIngestionService->createAlert(
            $this->currentDeviceProvider->requireDevice(),
            $data->clientAlertId,
            $data->fallTimestamp ?? new DateTimeImmutable(),
            $data->locale,
            $data->latitude,
            $data->longitude,
        );

        return FallAlertView::fromEntity($alert);
    }
}
