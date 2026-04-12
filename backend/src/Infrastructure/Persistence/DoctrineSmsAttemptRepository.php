<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\SmsAttemptRepositoryInterface;
use App\Entity\SmsAttempt;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<SmsAttempt>
 */
final class DoctrineSmsAttemptRepository extends ServiceEntityRepository implements SmsAttemptRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, SmsAttempt::class);
    }

    public function findOneByProviderMessageId(string $providerMessageId): ?SmsAttempt
    {
        return $this->findOneBy(['providerMessageId' => $providerMessageId]);
    }

    public function save(SmsAttempt $attempt): void
    {
        $this->getEntityManager()->persist($attempt);
        $this->getEntityManager()->flush();
    }
}
