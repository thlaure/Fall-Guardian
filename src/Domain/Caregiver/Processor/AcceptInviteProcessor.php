<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Request\AcceptInviteInputDTO;
use App\Domain\Caregiver\Service\InviteServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
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
