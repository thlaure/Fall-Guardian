<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use ApiPlatform\Metadata\Operation;
use App\Domain\Caregiver\Message\NotifyCaregiverLinkRevokedMessage;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\ProtectedPerson\Processor\RevokeCaregiverLinkProcessor;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Infrastructure\Http\Security\DeviceContextInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Uid\Uuid;

final class RevokeCaregiverLinkProcessorTest extends TestCase
{
    private DeviceContextInterface&MockObject $currentDeviceProvider;

    private CaregiverLinkRepositoryInterface&MockObject $caregiverLinkRepository;

    private MessageBusInterface&MockObject $messageBus;

    private RevokeCaregiverLinkProcessor $processor;

    protected function setUp(): void
    {
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->caregiverLinkRepository = $this->createMock(CaregiverLinkRepositoryInterface::class);
        $this->messageBus = $this->createMock(MessageBusInterface::class);

        $this->processor = new RevokeCaregiverLinkProcessor(
            $this->currentDeviceProvider,
            $this->caregiverLinkRepository,
            $this->messageBus,
        );
    }

    #[Test]
    public function itRevokesLinkWhenFoundAndOwned(): void
    {
        $device = $this->createMock(Device::class);
        $caregiverDevice = $this->createMock(Device::class);
        $link = $this->createMock(CaregiverLink::class);
        $id = Uuid::v7()->toRfc4122();
        $caregiverDeviceId = Uuid::v7();

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->caregiverLinkRepository
            ->method('findActiveByIdAndProtectedDevice')
            ->with($id, $device)
            ->willReturn($link);

        $caregiverDevice->method('getId')->willReturn($caregiverDeviceId);
        $link->method('getCaregiverDevice')->willReturn($caregiverDevice);
        $link->expects($this->once())->method('revoke');
        $this->caregiverLinkRepository->expects($this->once())->method('save')->with($link);

        $this->messageBus
            ->expects($this->once())
            ->method('dispatch')
            ->with($this->isInstanceOf(NotifyCaregiverLinkRevokedMessage::class))
            ->willReturn(new Envelope(new NotifyCaregiverLinkRevokedMessage($caregiverDeviceId->toRfc4122())));

        $result = $this->processor->process(null, $this->createMock(Operation::class), ['id' => $id]);

        $this->assertNull($result);
    }

    #[Test]
    public function itThrowsNotFoundWhenLinkDoesNotExist(): void
    {
        $device = $this->createMock(Device::class);
        $id = Uuid::v7()->toRfc4122();

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->caregiverLinkRepository
            ->method('findActiveByIdAndProtectedDevice')
            ->willReturn(null);

        $this->expectException(NotFoundHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['id' => $id]);
    }

    #[Test]
    public function itThrowsNotFoundWhenLinkBelongsToAnotherDevice(): void
    {
        $device = $this->createMock(Device::class);
        $id = Uuid::v7()->toRfc4122();

        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->caregiverLinkRepository
            ->method('findActiveByIdAndProtectedDevice')
            ->with($id, $device)
            ->willReturn(null);

        $this->expectException(NotFoundHttpException::class);

        $this->processor->process(null, $this->createMock(Operation::class), ['id' => $id]);
    }
}
