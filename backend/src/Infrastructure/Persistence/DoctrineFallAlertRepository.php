<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

/**
 * @extends ServiceEntityRepository<FallAlert>
 */
final class DoctrineFallAlertRepository extends ServiceEntityRepository implements FallAlertRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, FallAlert::class);
    }

    public function findOneByDeviceAndClientAlertId(Device $device, string $clientAlertId): ?FallAlert
    {
        return $this->findOneBy([
            'device' => $device,
            'clientAlertId' => $clientAlertId,
        ]);
    }

    public function findById(string $id): ?FallAlert
    {
        /** @var FallAlert|null $alert */
        $alert = $this->find(Uuid::fromString($id));

        return $alert;
    }

    /** @return list<FallAlert> */
    public function findByDevice(Device $device, int $limit = 50): array
    {
        /** @var list<FallAlert> $result */
        $result = $this->findBy(
            ['device' => $device],
            ['receivedAt' => 'DESC'],
            $limit,
        );

        return $result;
    }

    public function save(FallAlert $alert): void
    {
        $this->getEntityManager()->persist($alert);
        $this->getEntityManager()->flush();
    }
}
