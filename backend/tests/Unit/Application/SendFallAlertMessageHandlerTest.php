<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\Alert\Handler\SendFallAlertMessageHandler;
use App\Application\Contact\Handler\AlertMessageBuilder;
use App\Application\Contact\Handler\ContactCryptoService;
use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Contact\Port\EmergencyContactRepositoryInterface;
use App\Domain\Sms\Port\SmsGatewayInterface;
use App\Entity\Device;
use App\Entity\EmergencyContact;
use App\Entity\FallAlert;
use App\Message\SendFallAlertMessage;
use DateTimeImmutable;
use Doctrine\ORM\EntityManagerInterface;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use RuntimeException;

final class SendFallAlertMessageHandlerTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $fallAlertRepository;

    private EmergencyContactRepositoryInterface&MockObject $contactRepository;

    private ContactCryptoService $cryptoService;

    private SmsGatewayInterface&MockObject $smsGateway;

    private AlertMessageBuilder $messageBuilder;

    private EntityManagerInterface&MockObject $entityManager;

    private SendFallAlertMessageHandler $handler;

    /** Ciphertext of '+33600000000' encrypted with the test key used below. */
    private string $encryptedPhone;

    protected function setUp(): void
    {
        $this->fallAlertRepository = $this->createMock(FallAlertRepositoryInterface::class);
        $this->contactRepository = $this->createMock(EmergencyContactRepositoryInterface::class);
        // ContactCryptoService and AlertMessageBuilder are final — use real instances
        $this->cryptoService = new ContactCryptoService('test-enc-key-32-chars-padding-xx', 'test-hash-key');
        $this->encryptedPhone = $this->cryptoService->encrypt('+33600000000');
        $this->messageBuilder = new AlertMessageBuilder();
        $this->smsGateway = $this->createMock(SmsGatewayInterface::class);
        $this->entityManager = $this->createMock(EntityManagerInterface::class);

        $this->handler = new SendFallAlertMessageHandler(
            $this->fallAlertRepository,
            $this->contactRepository,
            $this->cryptoService,
            $this->smsGateway,
            $this->messageBuilder,
            $this->entityManager,
        );
    }

    #[Test]
    public function itSkipsUnknownAlert(): void
    {
        $this->fallAlertRepository->method('findById')->willReturn(null);
        $this->smsGateway->expects($this->never())->method('send');
        $this->entityManager->expects($this->never())->method('flush');

        ($this->handler)(new SendFallAlertMessage('unknown-id'));
    }

    #[Test]
    public function itSkipsCancelledAlert(): void
    {
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(new DateTimeImmutable());
        $this->fallAlertRepository->method('findById')->willReturn($alert);

        $this->smsGateway->expects($this->never())->method('send');

        ($this->handler)(new SendFallAlertMessage('some-id'));
    }

    #[Test]
    public function itMarksFailedWhenNoContacts(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(null);
        $alert->method('getDevice')->willReturn($device);
        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getLatitude')->willReturn(null);
        $alert->method('getLongitude')->willReturn(null);

        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->contactRepository->method('findByDevice')->willReturn([]);

        $alert->expects($this->once())->method('markDispatching');
        $alert->expects($this->once())->method('markFailed');
        $this->fallAlertRepository->expects($this->once())->method('save');
        $this->entityManager->expects($this->never())->method('flush');

        ($this->handler)(new SendFallAlertMessage('some-id'));
    }

    #[Test]
    public function itSendsSmsToAllContactsAndMarksAlertSent(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(null);
        $alert->method('getDevice')->willReturn($device);
        $alert->method('getId')->willReturn(\Symfony\Component\Uid\Uuid::v7());

        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getLatitude')->willReturn(null);
        $alert->method('getLongitude')->willReturn(null);

        $contact = $this->createMock(EmergencyContact::class);
        $contact->method('getPhoneCiphertext')->willReturn($this->encryptedPhone);

        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->contactRepository->method('findByDevice')->willReturn([$contact]);
        $this->smsGateway->method('getProviderName')->willReturn('fake');
        $this->smsGateway->method('send')->willReturn(['providerMessageId' => 'msg-001']);

        $alert->expects($this->once())->method('markDispatching');
        $alert->expects($this->once())->method('markSent');
        $alert->expects($this->once())->method('addSmsAttempt');
        $this->entityManager->expects($this->once())->method('persist');
        $this->entityManager->expects($this->once())->method('flush');

        ($this->handler)(new SendFallAlertMessage('some-id'));
    }

    #[Test]
    public function itMarksPartiallyWhenSomeSendsFail(): void
    {
        $device = $this->createMock(Device::class);
        $alert = $this->createMock(FallAlert::class);
        $alert->method('getCancelledAt')->willReturn(null);
        $alert->method('getDevice')->willReturn($device);
        $alert->method('getId')->willReturn(\Symfony\Component\Uid\Uuid::v7());

        $alert->method('getFallDetectedAt')->willReturn(new DateTimeImmutable());
        $alert->method('getLatitude')->willReturn(null);
        $alert->method('getLongitude')->willReturn(null);

        $contact1 = $this->createMock(EmergencyContact::class);
        $contact2 = $this->createMock(EmergencyContact::class);
        $contact1->method('getPhoneCiphertext')->willReturn($this->encryptedPhone);
        $contact2->method('getPhoneCiphertext')->willReturn($this->encryptedPhone);

        $this->fallAlertRepository->method('findById')->willReturn($alert);
        $this->contactRepository->method('findByDevice')->willReturn([$contact1, $contact2]);
        $this->smsGateway->method('getProviderName')->willReturn('fake');
        $this->smsGateway->method('send')
            ->willReturnOnConsecutiveCalls(
                ['providerMessageId' => 'msg-001'],
                $this->throwException(new RuntimeException('send failed')),
            );

        $alert->expects($this->once())->method('markPartiallySent');

        ($this->handler)(new SendFallAlertMessage('some-id'));
    }
}
