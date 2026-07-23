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
use App\Enum\FallAlertStatus;
use App\Infrastructure\Persistence\DoctrineAlertAcknowledgementRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverInviteRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverLinkRepository;
use App\Infrastructure\Persistence\DoctrineCaregiverPushTokenRepository;
use App\Infrastructure\Persistence\DoctrineDeviceRepository;
use App\Infrastructure\Persistence\DoctrineFallAlertRepository;
use App\Infrastructure\Persistence\DoctrinePushAttemptRepository;
use DateTimeImmutable;
use Doctrine\ORM\EntityManagerInterface;
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

    public function testFallAlertRepositoryAtomicallyClaimsDueAlertsAndRejectsLateCancellation(): void
    {
        self::bootKernel();

        $deviceRepository = self::getContainer()->get(DoctrineDeviceRepository::class);
        $alertRepository = self::getContainer()->get(DoctrineFallAlertRepository::class);
        self::assertInstanceOf(DoctrineDeviceRepository::class, $deviceRepository);
        self::assertInstanceOf(DoctrineFallAlertRepository::class, $alertRepository);

        $device = $this->device('claim-protected');
        $deviceRepository->save($device);
        $receivedAt = new DateTimeImmutable('2026-07-23T08:00:00+00:00');
        $alert = new FallAlert(
            $device,
            'claim-'.$this->suffix(),
            new DateTimeImmutable('2026-07-23T07:00:00+00:00'),
            'en',
            null,
            null,
            $receivedAt,
        );
        $alertRepository->save($alert);

        self::assertSame(
            [],
            $alertRepository->findDispatchCandidateIds(
                $receivedAt->modify('+29 seconds'),
                $receivedAt->modify('-1 minute'),
            ),
        );
        self::assertContains(
            $alert->getId()->toRfc4122(),
            $alertRepository->findDispatchCandidateIds(
                $receivedAt->modify('+30 seconds'),
                $receivedAt->modify('-1 minute'),
            ),
        );

        $claimed = $alertRepository->claimForDispatch(
            $alert->getId()->toRfc4122(),
            $receivedAt->modify('+30 seconds'),
            $receivedAt->modify('-1 minute'),
        );
        self::assertSame($alert, $claimed);
        self::assertSame(FallAlertStatus::Dispatching, $claimed->getStatus());

        $lateCancellation = $alertRepository->cancelPending(
            $device,
            $alert->getClientAlertId(),
            $receivedAt->modify('+31 seconds'),
        );
        self::assertSame(FallAlertStatus::Dispatching, $lateCancellation?->getStatus());
    }

    public function testHydratedUtcDeadlineAllowsImmediateCancellation(): void
    {
        self::bootKernel();

        self::assertSame('UTC', date_default_timezone_get());

        $deviceRepository = self::getContainer()->get(DoctrineDeviceRepository::class);
        $alertRepository = self::getContainer()->get(DoctrineFallAlertRepository::class);
        $entityManager = self::getContainer()->get(EntityManagerInterface::class);
        self::assertInstanceOf(DoctrineDeviceRepository::class, $deviceRepository);
        self::assertInstanceOf(DoctrineFallAlertRepository::class, $alertRepository);
        self::assertInstanceOf(EntityManagerInterface::class, $entityManager);

        $device = $this->device('utc-protected');
        $deviceRepository->save($device);
        $receivedAt = new DateTimeImmutable('2026-07-23T08:00:00+00:00');
        $alert = new FallAlert(
            $device,
            'utc-'.$this->suffix(),
            $receivedAt,
            'en',
            null,
            null,
            $receivedAt,
        );
        $alertRepository->save($alert);
        $alertId = $alert->getId()->toRfc4122();
        $clientAlertId = $alert->getClientAlertId();

        $entityManager->clear();
        $hydratedAlert = $alertRepository->findById($alertId);
        self::assertInstanceOf(FallAlert::class, $hydratedAlert);
        self::assertSame('UTC', $hydratedAlert->getCancelDeadlineAt()->getTimezone()->getName());

        $cancelled = $alertRepository->cancelPending(
            $hydratedAlert->getDevice(),
            $clientAlertId,
            $receivedAt->modify('+1 second'),
        );

        self::assertSame(FallAlertStatus::Cancelled, $cancelled?->getStatus());
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
