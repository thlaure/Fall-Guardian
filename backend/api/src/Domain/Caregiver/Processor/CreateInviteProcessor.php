<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Response\CreateInviteOutputDTO;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/**
 * @implements ProcessorInterface<CreateInviteOutputDTO, CreateInviteOutputDTO>
 */
final readonly class CreateInviteProcessor implements ProcessorInterface
{
    public function __construct(
        private InviteServiceInterface $inviteService,
        private DeviceContextInterface $currentDeviceProvider,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): CreateInviteOutputDTO
    {
        $device = $this->currentDeviceProvider->requireDevice();

        $this->rateLimiter->consume('invite_create', 10, 300, $device->getPublicId());

        try {
            $invite = $this->inviteService->createInvite($device);
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return CreateInviteOutputDTO::fromInviteData($invite->getCode(), $invite->getExpiresAt());
    }
}
