<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Caregiver\Handler\NotifyCaregiverLinkRevokedMessageHandler;
use App\Domain\Caregiver\Message\NotifyCaregiverLinkRevokedMessage;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Domain\Push\Port\PushGatewayInterface;
use App\Entity\CaregiverPushToken;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Uid\Uuid;

final class NotifyCaregiverLinkRevokedMessageHandlerTest extends TestCase
{
    private CaregiverPushTokenRepositoryInterface&MockObject $pushTokenRepository;

    private PushGatewayInterface&MockObject $pushGateway;

    private NotifyCaregiverLinkRevokedMessageHandler $handler;

    protected function setUp(): void
    {
        $this->pushTokenRepository = $this->createMock(CaregiverPushTokenRepositoryInterface::class);
        $this->pushGateway = $this->createMock(PushGatewayInterface::class);

        $this->handler = new NotifyCaregiverLinkRevokedMessageHandler(
            $this->pushTokenRepository,
            $this->pushGateway,
        );
    }

    #[Test]
    public function itSendsRevocationPushWhenTokenExists(): void
    {
        $deviceId = Uuid::v7()->toRfc4122();
        $fcmToken = 'fcm-token-abc';

        $token = $this->createMock(CaregiverPushToken::class);
        $token->method('getFcmToken')->willReturn($fcmToken);

        $this->pushTokenRepository
            ->method('findByDeviceId')
            ->with($deviceId)
            ->willReturn($token);

        $this->pushGateway
            ->expects($this->once())
            ->method('sendLinkRevoked')
            ->with($fcmToken)
            ->willReturn(['providerMessageId' => 'fake-id', 'status' => 'sent']);

        ($this->handler)(new NotifyCaregiverLinkRevokedMessage($deviceId));
    }

    #[Test]
    public function itSkipsWhenTokenNotFound(): void
    {
        $this->pushTokenRepository
            ->method('findByDeviceId')
            ->willReturn(null);

        $this->pushGateway
            ->expects($this->never())
            ->method('sendLinkRevoked');

        ($this->handler)(new NotifyCaregiverLinkRevokedMessage(Uuid::v7()->toRfc4122()));
    }
}
