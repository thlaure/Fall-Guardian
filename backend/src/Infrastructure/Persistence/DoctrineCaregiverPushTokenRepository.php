<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Caregiver\Port\CaregiverPushTokenRepositoryInterface;
use App\Entity\CaregiverPushToken;
use App\Entity\Device;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

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

    public function save(CaregiverPushToken $token): void
    {
        $this->getEntityManager()->persist($token);
        $this->getEntityManager()->flush();
    }
}
