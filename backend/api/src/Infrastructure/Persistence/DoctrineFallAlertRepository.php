<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Entity\ProtectedPerson;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\DBAL\LockMode;
use Doctrine\ORM\EntityManagerInterface;
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
        $protectedPerson = $device->getProtectedPerson();

        return $this->findOneBy([
            $protectedPerson instanceof ProtectedPerson ? 'protectedPerson' : 'device' => $protectedPerson ?? $device,
            'clientAlertId' => $clientAlertId,
        ]);
    }

    public function findById(string $id): ?FallAlert
    {
        /** @var FallAlert|null $alert */
        $alert = $this->find(Uuid::fromString($id));

        return $alert;
    }

    public function claimForDispatch(string $id, DateTimeImmutable $now, DateTimeImmutable $staleBefore): ?FallAlert
    {
        return $this->getEntityManager()->wrapInTransaction(
            static function (EntityManagerInterface $entityManager) use ($id, $now, $staleBefore): ?FallAlert {
                $alert = $entityManager->find(FallAlert::class, Uuid::fromString($id), LockMode::PESSIMISTIC_WRITE);

                if (!$alert instanceof FallAlert || !$alert->claimForDispatch($now, $staleBefore)) {
                    return null;
                }

                $entityManager->flush();

                return $alert;
            },
        );
    }

    public function cancelPending(Device $device, string $clientAlertId, DateTimeImmutable $now): ?FallAlert
    {
        return $this->getEntityManager()->wrapInTransaction(
            static function (EntityManagerInterface $entityManager) use ($device, $clientAlertId, $now): ?FallAlert {
                $queryBuilder = $entityManager->createQueryBuilder()
                    ->select('alert')
                    ->from(FallAlert::class, 'alert')
                    ->andWhere('alert.clientAlertId = :clientAlertId')
                    ->setParameter('clientAlertId', $clientAlertId)
                ;

                $protectedPerson = $device->getProtectedPerson();

                if ($protectedPerson instanceof ProtectedPerson) {
                    $queryBuilder
                        ->andWhere('alert.protectedPerson = :protectedPerson')
                        ->setParameter('protectedPerson', $protectedPerson);
                } else {
                    $queryBuilder
                        ->andWhere('alert.device = :device')
                        ->setParameter('device', $device);
                }

                $alert = $queryBuilder->getQuery()
                    ->setLockMode(LockMode::PESSIMISTIC_WRITE)
                    ->getOneOrNullResult();

                if (!$alert instanceof FallAlert) {
                    return null;
                }

                if ($alert->cancel($now)) {
                    $entityManager->flush();
                }

                return $alert;
            },
        );
    }

    public function findDispatchCandidateIds(DateTimeImmutable $now, DateTimeImmutable $staleBefore, int $limit = 100): array
    {
        /** @var list<array{id: Uuid|string}> $rows */
        $rows = $this->createQueryBuilder('alert')
            ->select('alert.id AS id')
            ->andWhere(
                '(alert.status = :received AND alert.cancelDeadlineAt <= :now)'
                .' OR (alert.status = :dispatching AND alert.dispatchClaimedAt <= :staleBefore)',
            )
            ->setParameter('received', FallAlertStatus::Received)
            ->setParameter('dispatching', FallAlertStatus::Dispatching)
            ->setParameter('now', $now)
            ->setParameter('staleBefore', $staleBefore)
            ->orderBy('alert.cancelDeadlineAt', 'ASC')
            ->setMaxResults($limit)
            ->getQuery()
            ->getArrayResult();

        return array_map(static fn (array $row): string => (string) $row['id'], $rows);
    }

    /** @return list<FallAlert> */
    public function findByDevice(Device $device, int $limit = 50): array
    {
        $protectedPerson = $device->getProtectedPerson();

        /** @var list<FallAlert> $result */
        $result = $this->findBy(
            [$protectedPerson instanceof ProtectedPerson ? 'protectedPerson' : 'device' => $protectedPerson ?? $device],
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
