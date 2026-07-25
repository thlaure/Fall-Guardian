<?php

declare(strict_types=1);

namespace App\Domain\Companion\Service;

use App\Domain\Device\Response\DeviceRegistrationOutputDTO;
use App\Entity\CompanionEnrollment;
use App\Entity\Device;
use App\Entity\ProtectedPerson;
use App\Infrastructure\Http\Security\DeviceTokenHasher;
use Doctrine\DBAL\LockMode;
use Doctrine\ORM\EntityManagerInterface;
use DomainException;
use Psr\Clock\ClockInterface;
use Symfony\Component\Uid\Uuid;

final readonly class CompanionEnrollmentService implements CompanionEnrollmentServiceInterface
{
    public const int TTL_SECONDS = 300;

    public function __construct(
        private EntityManagerInterface $entityManager,
        private DeviceTokenHasher $tokenHasher,
        private ClockInterface $clock,
    ) {
    }

    /** @return array{token: string, enrollment: CompanionEnrollment} */
    public function create(Device $device, string $platform): array
    {
        $protectedPerson = $device->getProtectedPerson();

        if ($device->isCaregiver() || !$protectedPerson instanceof ProtectedPerson) {
            throw new DomainException('Only a protected-person device can enroll a companion.');
        }

        if (!in_array($platform, ['watchos', 'wearos'], true)) {
            throw new DomainException('Unsupported companion platform.');
        }

        $token = $this->tokenHasher->generatePlainToken();
        $enrollment = new CompanionEnrollment(
            $protectedPerson,
            $device,
            $this->tokenHasher->hash($token),
            $platform,
            $this->clock->now()->modify(sprintf('+%d seconds', self::TTL_SECONDS)),
        );
        $this->entityManager->persist($enrollment);
        $this->entityManager->flush();

        return ['token' => $token, 'enrollment' => $enrollment];
    }

    public function claim(string $token, string $platform, string $appVersion): DeviceRegistrationOutputDTO
    {
        return $this->entityManager->wrapInTransaction(function (EntityManagerInterface $entityManager) use ($token, $platform, $appVersion): DeviceRegistrationOutputDTO {
            $enrollment = $entityManager->getRepository(CompanionEnrollment::class)
                ->createQueryBuilder('enrollment')
                ->andWhere('enrollment.tokenHash = :tokenHash')
                ->setParameter('tokenHash', $this->tokenHasher->hash($token))
                ->getQuery()
                ->setLockMode(LockMode::PESSIMISTIC_WRITE)
                ->getOneOrNullResult();

            if (!$enrollment instanceof CompanionEnrollment
                || $platform !== $enrollment->getPlatform()
                || !$enrollment->claim($this->clock->now())) {
                throw new DomainException('Enrollment token is invalid, expired, or already used.');
            }

            $plainDeviceToken = $this->tokenHasher->generatePlainToken();
            $device = new Device(
                Uuid::v7()->toRfc4122(),
                $this->tokenHasher->hash($plainDeviceToken),
                $platform,
                $appVersion,
            );
            $device->attachToProtectedPerson($enrollment->getProtectedPerson());
            $entityManager->persist($device);
            $entityManager->flush();

            return new DeviceRegistrationOutputDTO($device->getPublicId(), $plainDeviceToken);
        });
    }
}
