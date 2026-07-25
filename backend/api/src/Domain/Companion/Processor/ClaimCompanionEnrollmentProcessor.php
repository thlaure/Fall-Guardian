<?php

declare(strict_types=1);

namespace App\Domain\Companion\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Companion\Request\ClaimCompanionEnrollmentInputDTO;
use App\Domain\Companion\Service\CompanionEnrollmentServiceInterface;
use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Infrastructure\RateLimit\EndpointRateLimiterInterface;
use DomainException;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/** @implements ProcessorInterface<ClaimCompanionEnrollmentInputDTO, DeviceRegistrationOutputDTO> */
final readonly class ClaimCompanionEnrollmentProcessor implements ProcessorInterface
{
    public function __construct(
        private CompanionEnrollmentServiceInterface $service,
        private EndpointRateLimiterInterface $rateLimiter,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): DeviceRegistrationOutputDTO
    {
        if (!$data instanceof ClaimCompanionEnrollmentInputDTO) {
            throw new BadRequestHttpException('Invalid companion enrollment claim payload.');
        }

        $this->rateLimiter->consume('companion_enrollment_claim', 10, 300);

        try {
            return $this->service->claim($data->enrollmentToken, $data->platform, $data->appVersion);
        } catch (DomainException $exception) {
            throw new NotFoundHttpException($exception->getMessage(), $exception);
        }
    }
}
