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

use const JSON_THROW_ON_ERROR;

use JsonException;
use RuntimeException;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
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
        private RequestStack $requestStack,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        if (!$data instanceof AcceptInviteInputDTO) {
            throw new BadRequestHttpException('Expected accept invite payload.');
        }

        $rawCode = $uriVariables['code'] ?? '';
        $code = is_string($rawCode) ? $rawCode : '';
        $device = $this->currentDeviceProvider->requireDevice();

        $this->rateLimiter->consume('invite_accept', 5, 600, $device->getPublicId());

        try {
            $this->inviteService->acceptInvite(
                $code,
                $device,
                $this->resolveName($data->protectedPersonName, 'protectedPersonName'),
                $this->resolveName($data->caregiverName, 'caregiverName'),
            );
        } catch (RuntimeException $e) {
            throw new NotFoundHttpException($e->getMessage(), $e);
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        return null;
    }

    private function resolveName(?string $deserializedName, string $payloadKey): ?string
    {
        if (null !== $deserializedName) {
            return $deserializedName;
        }

        $request = $this->requestStack->getCurrentRequest();

        if (null === $request || '' === $request->getContent()) {
            return null;
        }

        try {
            /** @var mixed $payload */
            $payload = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            return null;
        }

        if (!is_array($payload) || !isset($payload[$payloadKey]) || !is_string($payload[$payloadKey])) {
            return null;
        }

        $name = trim($payload[$payloadKey]);

        if ('' === $name) {
            return null;
        }

        if (mb_strlen($name) < 2 || mb_strlen($name) > 120) {
            throw new UnprocessableEntityHttpException(sprintf('%s must be between 2 and 120 characters.', $payloadKey));
        }

        return $name;
    }
}
