<?php

declare(strict_types=1);

namespace App\UI\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\Caregiver\DTO\AcknowledgeAlertInput;
use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Entity\AlertAcknowledgement;
use App\Entity\FallAlert;
use App\Infrastructure\Http\Security\CurrentDeviceProvider;

use function is_string;

use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProcessorInterface<AcknowledgeAlertInput, null>
 */
final readonly class AcknowledgeAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private CurrentDeviceProvider $currentDeviceProvider,
        private FallAlertRepositoryInterface $fallAlertRepository,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private AlertAcknowledgementRepositoryInterface $acknowledgementRepository,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        $rawId = $uriVariables['id'] ?? '';
        $alertId = is_string($rawId) ? $rawId : '';

        $alert = $this->fallAlertRepository->findById($alertId);

        if (!$alert instanceof FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $caregiverDevice = $this->currentDeviceProvider->requireDevice();

        $links = $this->caregiverLinkRepository->findActiveByProtectedDevice($alert->getDevice());
        $isLinked = array_any($links, static fn ($link) => $link->getCaregiverDevice()->getId()->equals($caregiverDevice->getId()));

        if (!$isLinked) {
            throw new AccessDeniedHttpException('You are not linked to this protected person.');
        }

        $existing = $this->acknowledgementRepository->findByCaregiverAndAlert($alert, $caregiverDevice);

        if (!$existing instanceof AlertAcknowledgement) {
            $alert->markAcknowledged();
            $ack = new AlertAcknowledgement($alert, $caregiverDevice);
            $this->acknowledgementRepository->save($ack);
        }

        return null;
    }
}
