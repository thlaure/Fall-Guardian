<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Device\Port\DeviceRepositoryInterface;
use App\Entity\Device;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<Device>
 */
final class DoctrineDeviceRepository extends ServiceEntityRepository implements DeviceRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, Device::class);
    }

    public function findActiveByTokenHash(string $tokenHash): ?Device
    {
        return $this->findOneBy([
            'tokenHash' => $tokenHash,
            'revoked' => false,
        ]);
    }

    public function save(Device $device): void
    {
        $this->getEntityManager()->persist($device);
        $this->getEntityManager()->flush();
    }
}
