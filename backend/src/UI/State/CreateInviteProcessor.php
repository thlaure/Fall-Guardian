<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Caregiver\DTO\CreateInviteOutput;
use App\Application\Caregiver\Handler\InviteService;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;
use DomainException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/**
 * @implements ProcessorInterface<CreateInviteOutput, CreateInviteOutput>
 */
final readonly class CreateInviteProcessor implements ProcessorInterface
{
    public function __construct(
        private InviteService $inviteService,
        private CurrentDeviceProvider $currentDeviceProvider,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): CreateInviteOutput
    {
        try {
            $invite = $this->inviteService->createInvite(
                $this->currentDeviceProvider->requireDevice(),
            );
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return CreateInviteOutput::fromInviteData($invite->getCode(), $invite->getExpiresAt());
    }
}
