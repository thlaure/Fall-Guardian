<?php

declare(strict_types=1);

namespace App\Application\Caregiver\Handler;

use App\Domain\Caregiver\Port\CaregiverInviteRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Entity\CaregiverInvite;
use App\Entity\CaregiverLink;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use App\Enum\CaregiverLinkStatus;

use function bin2hex;

use DateTimeImmutable;
use DomainException;

use function random_bytes;

use RuntimeException;

use function sprintf;
use function strtoupper;
use function substr;

final readonly class InviteService
{
    private const int CODE_LENGTH = 8;

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

        $code = strtoupper(substr(bin2hex(random_bytes(4)), 0, self::CODE_LENGTH));
        $expiresAt = new DateTimeImmutable(sprintf('+%d minutes', self::TTL_MINUTES));

        $invite = new CaregiverInvite($protectedDevice, $code, $expiresAt);
        $this->inviteRepository->save($invite);

        return $invite;
    }

    public function acceptInvite(string $code, Device $caregiverDevice): CaregiverLink
    {
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
            if ($existing->getStatus() === CaregiverLinkStatus::Revoked) {
                throw new DomainException('This link has been revoked.');
            }
            $invite->markUsed();
            $this->inviteRepository->save($invite);

            return $existing;
        }

        $link = new CaregiverLink($protectedDevice, $caregiverDevice);
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
