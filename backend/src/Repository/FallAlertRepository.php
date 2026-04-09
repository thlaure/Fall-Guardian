<?php

declare(strict_types=1);

namespace App\Repository;

use App\Entity\Device;
use App\Entity\FallAlert;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<FallAlert>
 */
final class FallAlertRepository extends ServiceEntityRepository
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
}
