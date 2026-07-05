<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Service;

use App\Domain\Caregiver\Port\CaregiverInviteRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Entity\CaregiverInvite;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Enum\CaregiverLinkStatus;
use DateTimeImmutable;
use DomainException;
use RuntimeException;

final readonly class InviteService implements InviteServiceInterface
{
    private const int CODE_BYTES = 16;

    private const int TTL_MINUTES = 30;

    public function __construct(
        private CaregiverInviteRepositoryInterface $inviteRepository,
        private CaregiverLinkRepositoryInterface $linkRepository,
        private CaregiverPushTokenRepositoryInterface $pushTokenRepository,
    ) {
    }

    public function createInvite(Device $protectedDevice): CaregiverInvite
    {
        if ($protectedDevice->isCaregiver()) {
            throw new DomainException('Only protected-person devices can create invites.');
        }

        $code = strtoupper(bin2hex(random_bytes(self::CODE_BYTES)));
        $expiresAt = new DateTimeImmutable(sprintf('+%d minutes', self::TTL_MINUTES));

        $invite = new CaregiverInvite($protectedDevice, $code, $expiresAt);
        $this->inviteRepository->save($invite);

        return $invite;
    }

    public function acceptInvite(
        string $code,
        Device $caregiverDevice,
        ?string $protectedPersonName = null,
        ?string $caregiverName = null,
    ): CaregiverLink {
        if (!$caregiverDevice->isCaregiver()) {
            throw new DomainException('Only caregiver devices can accept invites.');
        }

        $invite = $this->inviteRepository->findActiveByCode($code);

        if (!$invite instanceof CaregiverInvite) {
            throw new RuntimeException('Invite not found, expired, or already used.');
        }

        $protectedDevice = $invite->getDevice();

        $existing = $this->linkRepository->findExistingPair($protectedDevice, $caregiverDevice);

        if ($existing instanceof CaregiverLink) {
            if (CaregiverLinkStatus::Revoked === $existing->getStatus()) {
                $existing->reactivate();
            }

            if (null !== $protectedPersonName) {
                $existing->renameProtectedPerson($protectedPersonName);
            }

            if (null !== $caregiverName) {
                $existing->renameCaregiver($caregiverName);
            }
            $invite->markUsed();
            $this->inviteRepository->save($invite);
            $this->linkRepository->save($existing);

            return $existing;
        }

        $link = new CaregiverLink($protectedDevice, $caregiverDevice);

        if (null !== $protectedPersonName) {
            $link->renameProtectedPerson($protectedPersonName);
        }

        if (null !== $caregiverName) {
            $link->renameCaregiver($caregiverName);
        }
        $invite->markUsed();

        $this->inviteRepository->save($invite);
        $this->linkRepository->save($link);

        return $link;
    }

    public function registerPushToken(Device $caregiverDevice, string $fcmToken): CaregiverPushToken
    {
        if (!$caregiverDevice->isCaregiver()) {
            throw new DomainException('Only caregiver devices can register push tokens.');
        }

        $token = $this->pushTokenRepository->findByDevice($caregiverDevice);

        if ($token instanceof CaregiverPushToken) {
            $token->update($fcmToken);
        } else {
            $token = new CaregiverPushToken($caregiverDevice, $fcmToken);
        }

        $this->pushTokenRepository->save($token);

        return $token;
    }
}
