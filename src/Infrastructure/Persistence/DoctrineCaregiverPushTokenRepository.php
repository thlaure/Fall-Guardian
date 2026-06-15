<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use InvalidArgumentException;
use Symfony\Component\Uid\Uuid;

/**
 * @extends ServiceEntityRepository<CaregiverPushToken>
 */
final class DoctrineCaregiverPushTokenRepository extends ServiceEntityRepository implements CaregiverPushTokenRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, CaregiverPushToken::class);
    }

    public function findByDevice(Device $device): ?CaregiverPushToken
    {
        /** @var CaregiverPushToken|null $token */
        $token = $this->findOneBy(['device' => $device]);

        return $token;
    }

    public function findByDeviceId(string $deviceId): ?CaregiverPushToken
    {
        try {
            $uuid = Uuid::fromString($deviceId);
        } catch (InvalidArgumentException) {
            return null;
        }

        /** @var CaregiverPushToken|null $token */
        $token = $this->createQueryBuilder('t')
            ->join('t.device', 'd')
            ->andWhere('d.id = :id')
            ->setParameter('id', $uuid, 'uuid')
            ->getQuery()
            ->getOneOrNullResult();

        return $token;
    }

    public function save(CaregiverPushToken $token): void
    {
        $this->getEntityManager()->persist($token);
        $this->getEntityManager()->flush();
    }
}
