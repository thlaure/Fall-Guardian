<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\PushAttemptRepositoryInterface;
use App\Entity\PushAttempt;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<PushAttempt>
 */
final class DoctrinePushAttemptRepository extends ServiceEntityRepository implements PushAttemptRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, PushAttempt::class);
    }

    public function save(PushAttempt $attempt): void
    {
        $this->getEntityManager()->persist($attempt);
        $this->getEntityManager()->flush();
    }
}
