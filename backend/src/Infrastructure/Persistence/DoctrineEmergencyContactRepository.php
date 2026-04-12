<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Contact\Port\EmergencyContactRepositoryInterface;
use App\Entity\Device;
use App\Entity\EmergencyContact;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<EmergencyContact>
 */
final class DoctrineEmergencyContactRepository extends ServiceEntityRepository implements EmergencyContactRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, EmergencyContact::class);
    }

    /** @return list<EmergencyContact> */
    public function findByDevice(Device $device): array
    {
        /** @var list<EmergencyContact> $result */
        $result = $this->createQueryBuilder('contact')
            ->andWhere('contact.device = :device')
            ->setParameter('device', $device)
            ->orderBy('contact.position', 'ASC')
            ->getQuery()
            ->getResult();

        return $result;
    }

    public function deleteForDevice(Device $device): void
    {
        $this->createQueryBuilder('contact')
            ->delete()
            ->andWhere('contact.device = :device')
            ->setParameter('device', $device)
            ->getQuery()
            ->execute();
    }
}
