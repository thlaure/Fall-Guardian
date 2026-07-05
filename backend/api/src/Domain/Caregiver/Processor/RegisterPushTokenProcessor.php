<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Request\RegisterPushTokenInputDTO;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/**
 * @implements ProcessorInterface<RegisterPushTokenInputDTO, null>
 */
final readonly class RegisterPushTokenProcessor implements ProcessorInterface
{
    public function __construct(
        private InviteServiceInterface $inviteService,
        private DeviceContextInterface $currentDeviceProvider,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        if (!$data instanceof RegisterPushTokenInputDTO) {
            throw new BadRequestHttpException('Invalid push token payload.');
        }

        $device = $this->currentDeviceProvider->requireDevice();

        $this->rateLimiter->consume('register_push_token', 10, 60, $device->getPublicId());

        try {
            $this->inviteService->registerPushToken($device, $data->fcmToken);
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return null;
    }
}
