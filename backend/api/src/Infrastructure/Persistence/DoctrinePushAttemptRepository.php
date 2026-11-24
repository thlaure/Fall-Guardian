<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\PushAttemptRepositoryInterface;
use App\Entity\FallAlert;
use App\Entity\PushAttempt;
use App\Enum\PushAttemptStatus;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

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

    public function findSentCaregiverDeviceIds(FallAlert $alert, int $reminderNumber): array
    {
        /** @var list<array{id: Uuid|string}> $rows */
        $rows = $this->createQueryBuilder('attempt')
            ->select('IDENTITY(attempt.caregiverDevice) AS id')
            ->andWhere('attempt.fallAlert = :alert')
            ->andWhere('attempt.reminderNumber = :reminderNumber')
            ->andWhere('attempt.status = :sent')
            ->setParameter('alert', $alert->getId(), 'uuid')
            ->setParameter('reminderNumber', $reminderNumber)
            ->setParameter('sent', PushAttemptStatus::Sent->value)
            ->distinct()
            ->getQuery()
            ->getArrayResult();

        return array_values(array_map(
            static fn (array $row): string => $row['id'] instanceof Uuid ? $row['id']->toRfc4122() : Uuid::fromString((string) $row['id'])->toRfc4122(),
            $rows,
        ));
    }
}
