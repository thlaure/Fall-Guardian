<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\Device;
use App\Entity\FallAlert;
use App\Entity\ProtectedPerson;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;
use DateTimeZone;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\DBAL\LockMode;
use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\EntityManagerInterface;
use Doctrine\Persistence\ManagerRegistry;
use InvalidArgumentException;
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
        $uuid = self::parseUuid($id);

        if (!$uuid instanceof Uuid) {
            return null;
        }

        /** @var FallAlert|null $alert */
        $alert = $this->find($uuid);

        return $alert;
    }

    public function claimForDispatch(string $id, DateTimeImmutable $now, DateTimeImmutable $staleBefore): ?FallAlert
    {
        $uuid = self::parseUuid($id);

        if (!$uuid instanceof Uuid) {
            return null;
        }

        return $this->getEntityManager()->wrapInTransaction(
            static function (EntityManagerInterface $entityManager) use ($uuid, $now, $staleBefore): ?FallAlert {
                $alert = $entityManager->find(FallAlert::class, $uuid, LockMode::PESSIMISTIC_WRITE);

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
                .' OR (alert.status = :dispatching AND alert.dispatchClaimedAt <= :staleBefore)'
                .' OR (alert.status IN (:retryable) AND alert.nextDispatchRetryAt <= :now AND alert.dispatchAttempts < :maxAttempts)',
            )
            ->setParameter('received', FallAlertStatus::Received)
            ->setParameter('dispatching', FallAlertStatus::Dispatching)
            ->setParameter('retryable', [FallAlertStatus::Failed->value, FallAlertStatus::PartiallySent->value])
            ->setParameter('maxAttempts', FallAlert::MAX_DISPATCH_ATTEMPTS)
            ->setParameter('now', $now, Types::DATETIME_IMMUTABLE)
            ->setParameter('staleBefore', $staleBefore, Types::DATETIME_IMMUTABLE)
            ->orderBy('alert.cancelDeadlineAt', 'ASC')
            ->setMaxResults($limit)
            ->getQuery()
            ->getArrayResult();

        return array_map(static fn (array $row): string => (string) $row['id'], $rows);
    }

    public function touchDispatchClaim(string $id, DateTimeImmutable $now): void
    {
        $uuid = self::parseUuid($id);

        if (!$uuid instanceof Uuid) {
            return;
        }

        $this->getEntityManager()->createQuery(
            'UPDATE '.FallAlert::class.' alert SET alert.dispatchClaimedAt = :now WHERE alert.id = :id AND alert.status = :dispatching',
        )
            ->setParameter('now', $now, Types::DATETIME_IMMUTABLE)
            ->setParameter('id', $uuid, 'uuid')
            ->setParameter('dispatching', FallAlertStatus::Dispatching->value)
            ->execute();
    }

    public function completeDispatch(string $id, FallAlertStatus $status, ?DateTimeImmutable $nextRetryAt): bool
    {
        $uuid = self::parseUuid($id);

        if (!$uuid instanceof Uuid) {
            return false;
        }

        $affected = $this->getEntityManager()->createQuery(
            'UPDATE '.FallAlert::class.' alert'
            .' SET alert.status = :status, alert.nextDispatchRetryAt = :nextRetryAt'
            .' WHERE alert.id = :id AND alert.status = :dispatching',
        )
            ->setParameter('status', $status->value)
            ->setParameter('nextRetryAt', $nextRetryAt, Types::DATETIME_IMMUTABLE)
            ->setParameter('id', $uuid, 'uuid')
            ->setParameter('dispatching', FallAlertStatus::Dispatching->value)
            ->execute();

        return 1 === $affected;
    }

    public function findReminderCandidates(DateTimeImmutable $now, DateTimeImmutable $lastReminderBefore, int $maxReminders, int $limit = 100): array
    {
        /** @var list<array{id: Uuid|string, reminderCount: int}> $rows */
        $rows = $this->createQueryBuilder('alert')
            ->select('alert.id AS id', 'alert.reminderCount AS reminderCount')
            ->andWhere('alert.status IN (:remindable)')
            ->andWhere('alert.acknowledgementDeadlineAt <= :now')
            ->andWhere('alert.acknowledgementDeadlineAt > :windowStart')
            ->andWhere('alert.reminderCount < :maxReminders')
            ->andWhere('alert.lastReminderAt IS NULL OR alert.lastReminderAt <= :lastReminderBefore')
            ->setParameter('remindable', [FallAlertStatus::Sent->value, FallAlertStatus::PartiallySent->value])
            ->setParameter('now', $now, Types::DATETIME_IMMUTABLE)
            ->setParameter('windowStart', $now->modify(sprintf('-%d seconds', FallAlert::REMINDER_WINDOW_SECONDS)), Types::DATETIME_IMMUTABLE)
            ->setParameter('maxReminders', $maxReminders)
            ->setParameter('lastReminderBefore', $lastReminderBefore, Types::DATETIME_IMMUTABLE)
            ->orderBy('alert.acknowledgementDeadlineAt', 'ASC')
            ->setMaxResults($limit)
            ->getQuery()
            ->getArrayResult();

        return array_map(
            static fn (array $row): array => ['id' => (string) $row['id'], 'reminderCount' => (int) $row['reminderCount']],
            $rows,
        );
    }

    public function claimReminder(string $id, int $expectedReminderCount, DateTimeImmutable $now): bool
    {
        $uuid = self::parseUuid($id);

        if (!$uuid instanceof Uuid) {
            return false;
        }

        $affected = $this->getEntityManager()->createQuery(
            'UPDATE '.FallAlert::class.' alert'
            .' SET alert.reminderCount = alert.reminderCount + 1, alert.lastReminderAt = :now'
            .' WHERE alert.id = :id AND alert.reminderCount = :expected AND alert.status IN (:remindable)',
        )
            ->setParameter('now', $now, Types::DATETIME_IMMUTABLE)
            ->setParameter('id', $uuid, 'uuid')
            ->setParameter('expected', $expectedReminderCount)
            ->setParameter('remindable', [FallAlertStatus::Sent->value, FallAlertStatus::PartiallySent->value])
            ->execute();

        return 1 === $affected;
    }

    public function findOldestPendingEscalationDueAt(DateTimeImmutable $now): ?DateTimeImmutable
    {
        $candidates = [
            $this->minimum('alert.cancelDeadlineAt', 'alert.status = :status AND alert.cancelDeadlineAt <= :now', FallAlertStatus::Received, $now),
            $this->minimum('alert.dispatchClaimedAt', 'alert.status = :status AND alert.dispatchClaimedAt <= :now', FallAlertStatus::Dispatching, $now),
            $this->minimum(
                'alert.nextDispatchRetryAt',
                'alert.status IN (:status, :otherStatus) AND alert.nextDispatchRetryAt <= :now',
                FallAlertStatus::Failed,
                $now,
                FallAlertStatus::PartiallySent,
            ),
        ];
        $candidates = array_values(array_filter($candidates));

        return [] === $candidates ? null : min($candidates);
    }

    private function minimum(string $field, string $condition, FallAlertStatus $status, DateTimeImmutable $now, ?FallAlertStatus $otherStatus = null): ?DateTimeImmutable
    {
        $query = $this->getEntityManager()->createQuery(
            sprintf('SELECT MIN(%s) FROM %s alert WHERE %s', $field, FallAlert::class, $condition),
        )
            ->setParameter('status', $status->value)
            ->setParameter('now', $now, Types::DATETIME_IMMUTABLE);

        if ($otherStatus instanceof FallAlertStatus) {
            $query->setParameter('otherStatus', $otherStatus->value);
        }

        $value = $query->getSingleScalarResult();

        return is_string($value) ? new DateTimeImmutable($value, new DateTimeZone('UTC')) : null;
    }

    private static function parseUuid(string $id): ?Uuid
    {
        try {
            return Uuid::fromString($id);
        } catch (InvalidArgumentException) {
            return null;
        }
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
