<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Request\AcceptInviteInputDTO;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use RuntimeException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/**
 * @implements ProcessorInterface<AcceptInviteInputDTO, null>
 */
final readonly class AcceptInviteProcessor implements ProcessorInterface
{
    public function __construct(
        private InviteServiceInterface $inviteService,
        private DeviceContextInterface $currentDeviceProvider,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        $rawCode = $uriVariables['code'] ?? '';
        $code = is_string($rawCode) ? $rawCode : '';
        $device = $this->currentDeviceProvider->requireDevice();

        $this->rateLimiter->consume('invite_accept', 5, 600, $device->getPublicId());

        try {
            $this->inviteService->acceptInvite(
                $code,
                $device,
            );
        } catch (RuntimeException $e) {
            throw new NotFoundHttpException($e->getMessage(), $e);
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return null;
    }
}
