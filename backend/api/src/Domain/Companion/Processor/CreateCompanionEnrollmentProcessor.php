<?php

declare(strict_types=1);

namespace App\Domain\Companion\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Companion\Request\CreateCompanionEnrollmentInputDTO;
use App\Domain\Companion\Response\CreateCompanionEnrollmentOutputDTO;
use App\Domain\Companion\Service\CompanionEnrollmentServiceInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;

/** @implements ProcessorInterface<CreateCompanionEnrollmentInputDTO, CreateCompanionEnrollmentOutputDTO> */
final readonly class CreateCompanionEnrollmentProcessor implements ProcessorInterface
{
    public function __construct(
        private CompanionEnrollmentServiceInterface $service,
        private DeviceContextInterface $deviceContext,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): CreateCompanionEnrollmentOutputDTO
    {
        if (!$data instanceof CreateCompanionEnrollmentInputDTO) {
            throw new BadRequestHttpException('Invalid companion enrollment payload.');
        }

        $device = $this->deviceContext->requireDevice();
        $this->rateLimiter->consume('companion_enrollment_create', 5, 300, $device->getPublicId());

        try {
            $result = $this->service->create($device, $data->platform);
        } catch (DomainException $exception) {
            throw new UnprocessableEntityHttpException($exception->getMessage(), $exception);
        }

        return CreateCompanionEnrollmentOutputDTO::create(
            $result['token'],
            $result['enrollment']->getExpiresAt(),
        );
    }
}
