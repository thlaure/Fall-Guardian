<?php

declare(strict_types=1);

namespace App\Tests\Integration\Infrastructure;

use App\Entity\AlertAcknowledgement;
use App\Entity\CaregiverInvite;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Entity\PushAttempt;
use App\Enum\DeviceType;
use App\Infrastructure\Persistence\DoctrineAlertAcknowledgementRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverInviteRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverLinkRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverPushTokenRepository;
use App\Infrastructure\Persistence\DoctrineDeviceRepository;
use App\Infrastructure\Persistence\DoctrineFallAlertRepository;
use App\Infrastructure\Persistence\DoctrinePushAttemptRepository;
use DateTimeImmutable;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;

final class DoctrineRepositoryTest extends KernelTestCase
{
    public function testDeviceAndFallAlertRepositoriesPersistAndFindEntities(): void
    {
        self::bootKernel();

        $deviceRepository = self::getContainer()->get(DoctrineDeviceRepository::class);
        self::assertInstanceOf(DoctrineDeviceRepository::class, $deviceRepository);
        $alertRepository = self::getContainer()->get(DoctrineFallAlertRepository::class);
        self::assertInstanceOf(DoctrineFallAlertRepository::class, $alertRepository);

        $device = $this->device('protected');
        $deviceRepository->save($device);

        self::assertSame($device, $deviceRepository->findActiveByTokenHash($device->getTokenHash()));

        $alert = new FallAlert($device, 'client-'.$this->suffix(), new DateTimeImmutable(), 'en', 48.8, 2.3);
        $alertRepository->save($alert);

        self::assertSame($alert, $alertRepository->findOneByDeviceAndClientAlertId($device, $alert->getClientAlertId()));
        self::assertSame($alert, $alertRepository->findById($alert->getId()->toRfc4122()));
        self::assertSame([$alert], $alertRepository->findByDevice($device, 10));
    }

    public function testCaregiverRepositoriesPersistAndFindLinksInvitesTokensAndAcknowledgements(): void
    {
        self::bootKernel();

        $deviceRepository = self::getContainer()->get(DoctrineDeviceRepository::class);
        self::assertInstanceOf(DoctrineDeviceRepository::class, $deviceRepository);
        $inviteRepository = self::getContainer()->get(DoctrineCaregiverInviteRepository::class);
        self::assertInstanceOf(DoctrineCaregiverInviteRepository::class, $inviteRepository);
        $linkRepository = self::getContainer()->get(DoctrineCaregiverLinkRepository::class);
        self::assertInstanceOf(DoctrineCaregiverLinkRepository::class, $linkRepository);
        $tokenRepository = self::getContainer()->get(DoctrineCaregiverPushTokenRepository::class);
        self::assertInstanceOf(DoctrineCaregiverPushTokenRepository::class, $tokenRepository);
        $alertRepository = self::getContainer()->get(DoctrineFallAlertRepository::class);
        self::assertInstanceOf(DoctrineFallAlertRepository::class, $alertRepository);
        $ackRepository = self::getContainer()->get(DoctrineAlertAcknowledgementRepository::class);
        self::assertInstanceOf(DoctrineAlertAcknowledgementRepository::class, $ackRepository);
        $pushAttemptRepository = self::getContainer()->get(DoctrinePushAttemptRepository::class);
        self::assertInstanceOf(DoctrinePushAttemptRepository::class, $pushAttemptRepository);

        $protectedDevice = $this->device('protected');
        $caregiverDevice = $this->device('caregiver');
        $caregiverDevice->setDeviceType(DeviceType::Caregiver);
        $deviceRepository->save($protectedDevice);
        $deviceRepository->save($caregiverDevice);

        $code = substr('A'.$this->suffix(), 0, 8);
        $invite = new CaregiverInvite($protectedDevice, $code, new DateTimeImmutable('+1 hour'));
        $inviteRepository->save($invite);

        self::assertSame($invite, $inviteRepository->findActiveByCode($code));

        $link = new CaregiverLink($protectedDevice, $caregiverDevice);
        $linkRepository->save($link);

        self::assertSame([$link], $linkRepository->findActiveByProtectedDevice($protectedDevice));
        self::assertSame($link, $linkRepository->findActiveByIdAndProtectedDevice($link->getId()->toRfc4122(), $protectedDevice));
        self::assertNull($linkRepository->findActiveByIdAndProtectedDevice('not-a-uuid', $protectedDevice));
        self::assertSame($link, $linkRepository->findExistingPair($protectedDevice, $caregiverDevice));
        self::assertSame([$link], $linkRepository->findByCaregiverDevice($caregiverDevice));

        $token = new CaregiverPushToken($caregiverDevice, 'fcm-token-'.$this->suffix());
        $tokenRepository->save($token);

        self::assertSame($token, $tokenRepository->findByDevice($caregiverDevice));
        self::assertSame($token, $tokenRepository->findByDeviceId($caregiverDevice->getId()->toRfc4122()));
        self::assertNull($tokenRepository->findByDeviceId('not-a-uuid'));

        $link->revoke();
        $linkRepository->save($link);

        self::assertNull($linkRepository->findActiveByIdAndProtectedDevice($link->getId()->toRfc4122(), $protectedDevice));
        self::assertSame([], $linkRepository->findActiveByProtectedDevice($protectedDevice));
        $link->reactivate();
        $linkRepository->save($link);

        $alert = new FallAlert($protectedDevice, 'client-'.$this->suffix(), new DateTimeImmutable(), 'en', null, null);
        $alertRepository->save($alert);

        $ack = new AlertAcknowledgement($alert, $caregiverDevice);
        $ackRepository->save($ack);

        self::assertSame($ack, $ackRepository->findByCaregiverAndAlert($alert, $caregiverDevice));

        $attempt = new PushAttempt($alert, $caregiverDevice, 'fake');
        $pushAttemptRepository->save($attempt);

        self::assertNotNull($attempt->getId());
    }

    private function device(string $prefix): Device
    {
        return new Device($prefix.'-'.$this->suffix(), hash('sha256', $prefix.$this->suffix()), 'ios', '1.0.0');
    }

    private function suffix(): string
    {
        return bin2hex(random_bytes(8));
    }
}
