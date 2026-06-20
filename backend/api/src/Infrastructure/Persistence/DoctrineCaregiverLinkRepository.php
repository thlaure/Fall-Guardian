<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Caregiver\Port\CaregiverLinkRepositoryInterface;
use App\Entity\CaregiverLink;
use App\Entity\Device;
use App\Enum\CaregiverLinkStatus;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use InvalidArgumentException;
use Symfony\Component\Uid\Uuid;

/**
 * @extends ServiceEntityRepository<CaregiverLink>
 */
final class DoctrineCaregiverLinkRepository extends ServiceEntityRepository implements CaregiverLinkRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, CaregiverLink::class);
    }

    /** @return list<CaregiverLink> */
    public function findActiveByProtectedDevice(Device $protectedDevice): array
    {
        /** @var list<CaregiverLink> $result */
        $result = $this->createQueryBuilder('link')
            ->andWhere('link.protectedDevice = :device')
            ->andWhere('link.status = :status')
            ->setParameter('device', $protectedDevice)
            ->setParameter('status', CaregiverLinkStatus::Active)
            ->getQuery()
            ->getResult();

        return $result;
    }

    public function findActiveByIdAndProtectedDevice(string $id, Device $protectedDevice): ?CaregiverLink
    {
        try {
            $uuid = Uuid::fromString($id);
        } catch (InvalidArgumentException) {
            return null;
        }

        /** @var CaregiverLink|null $result */
        $result = $this->createQueryBuilder('link')
            ->andWhere('link.id = :id')
            ->andWhere('link.protectedDevice = :device')
            ->andWhere('link.status = :status')
            ->setParameter('id', $uuid, 'uuid')
            ->setParameter('device', $protectedDevice)
            ->setParameter('status', CaregiverLinkStatus::Active)
            ->getQuery()
            ->getOneOrNullResult();

        return $result;
    }

    public function findExistingPair(Device $protectedDevice, Device $caregiverDevice): ?CaregiverLink
    {
        /** @var CaregiverLink|null $link */
        $link = $this->createQueryBuilder('link')
            ->andWhere('link.protectedDevice = :protected')
            ->andWhere('link.caregiverDevice = :caregiver')
            ->setParameter('protected', $protectedDevice)
            ->setParameter('caregiver', $caregiverDevice)
            ->getQuery()
            ->getOneOrNullResult();

        return $link;
    }

    /** @return list<CaregiverLink> */
    public function findByCaregiverDevice(Device $caregiverDevice): array
    {
        /** @var list<CaregiverLink> $result */
        $result = $this->createQueryBuilder('link')
            ->andWhere('link.caregiverDevice = :device')
            ->andWhere('link.status = :status')
            ->setParameter('device', $caregiverDevice)
            ->setParameter('status', CaregiverLinkStatus::Active)
            ->getQuery()
            ->getResult();

        return $result;
    }

    public function save(CaregiverLink $link): void
    {
        $this->getEntityManager()->persist($link);
        $this->getEntityManager()->flush();
    }
}
