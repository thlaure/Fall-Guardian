<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Caregiver\DTO\AcceptInviteInput;
use App\Application\Caregiver\Handler\InviteService;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;
use DomainException;

use function is_string;

use RuntimeException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/**
 * @implements ProcessorInterface<AcceptInviteInput, null>
 */
final readonly class AcceptInviteProcessor implements ProcessorInterface
{
    public function __construct(
        private InviteService $inviteService,
        private CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        $rawCode = $uriVariables['code'] ?? '';
        $code = is_string($rawCode) ? $rawCode : '';

        try {
            $this->inviteService->acceptInvite(
                $code,
                $this->currentDeviceProvider->requireDevice(),
            );
        } catch (RuntimeException $e) {
            throw new NotFoundHttpException($e->getMessage(), $e);
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return null;
    }
}
