<?php

declare(strict_types=1);

namespace App\Domain\ProtectedPerson\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Caregiver\Message\NotifyCaregiverLinkRevokedMessage;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Messenger\MessageBusInterface;

/**
 * @implements ProcessorInterface<null, null>
 */
final readonly class RevokeCaregiverLinkProcessor implements ProcessorInterface
{
    public function __construct(
        private DeviceContextInterface $currentDeviceProvider,
        private CaregiverLinkRepositoryInterface $caregiverLinkRepository,
        private MessageBusInterface $messageBus,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): null
    {
        $rawId = $uriVariables['id'] ?? '';
        $id = is_string($rawId) ? $rawId : '';

        $device = $this->currentDeviceProvider->requireDevice();

        $link = $this->caregiverLinkRepository->findActiveByIdAndProtectedDevice($id, $device);

        if (null === $link) {
            throw new NotFoundHttpException('Caregiver link not found.');
        }

        $caregiverDeviceId = $link->getCaregiverDevice()->getId()->toRfc4122();

        $link->revoke();
        $this->caregiverLinkRepository->save($link);

        $this->messageBus->dispatch(new NotifyCaregiverLinkRevokedMessage($caregiverDeviceId));

        return null;
    }
}
