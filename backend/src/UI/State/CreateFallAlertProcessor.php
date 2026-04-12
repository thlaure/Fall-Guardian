<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Alert\DTO\CreateFallAlertInput;
use App\Application\Alert\DTO\FallAlertView;
use App\Application\Alert\Handler\AlertIngestionService;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;

use function assert;

use DateTimeImmutable;

/**
 * @implements ProcessorInterface<CreateFallAlertInput, FallAlertView>
 */
final readonly class CreateFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionService $alertIngestionService,
        private CurrentDeviceProvider $currentDeviceProvider,
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
