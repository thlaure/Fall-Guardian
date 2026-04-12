<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Caregiver\DTO\RegisterPushTokenInput;
use App\Application\Caregiver\Handler\InviteService;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;

use function assert;

use DomainException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/**
 * @implements ProcessorInterface<RegisterPushTokenInput, null>
 */
final readonly class RegisterPushTokenProcessor implements ProcessorInterface
{
    public function __construct(
        private InviteService $inviteService,
        private CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        assert($data instanceof RegisterPushTokenInput);

        try {
            $this->inviteService->registerPushToken(
                $this->currentDeviceProvider->requireDevice(),
                $data->fcmToken,
            );
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return null;
    }
}
