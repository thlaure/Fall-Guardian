<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Caregiver\Port\CaregiverInviteRepositoryInterface;
use App\Entity\CaregiverInvite;
use DateTimeImmutable;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<CaregiverInvite>
 */
final class DoctrineCaregiverInviteRepository extends ServiceEntityRepository implements CaregiverInviteRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, CaregiverInvite::class);
    }

    public function findActiveByCode(string $code): ?CaregiverInvite
    {
        /** @var CaregiverInvite|null $invite */
        $invite = $this->createQueryBuilder('invite')
            ->andWhere('invite.code = :code')
            ->andWhere('invite.usedAt IS NULL')
            ->andWhere('invite.expiresAt > :now')
            ->setParameter('code', $code)
            ->setParameter('now', new DateTimeImmutable())
            ->getQuery()
            ->getOneOrNullResult();

        return $invite;
    }

    public function save(CaregiverInvite $invite): void
    {
        $this->getEntityManager()->persist($invite);
        $this->getEntityManager()->flush();
    }
}
