<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Entity\AlertAcknowledgement;
use App\Entity\Device;
use App\Entity\FallAlert;
use DateTimeImmutable;
use DateTimeZone;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

/**
 * @extends ServiceEntityRepository<AlertAcknowledgement>
 */
final class DoctrineAlertAcknowledgementRepository extends ServiceEntityRepository implements AlertAcknowledgementRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, AlertAcknowledgement::class);
    }

    public function findByCaregiverAndAlert(FallAlert $alert, Device $caregiverDevice): ?AlertAcknowledgement
    {
        /** @var AlertAcknowledgement|null $ack */
        $ack = $this->findOneBy([
            'fallAlert' => $alert,
            'caregiverDevice' => $caregiverDevice,
        ]);

        return $ack;
    }

    public function summarizeByAlerts(array $alerts): array
    {
        if ([] === $alerts) {
            return [];
        }

        /** @var list<array{alertId: Uuid|string, ackCount: int|string, firstAt: string|null}> $rows */
        $rows = $this->createQueryBuilder('ack')
            ->select('IDENTITY(ack.fallAlert) AS alertId', 'COUNT(ack.id) AS ackCount', 'MIN(ack.acknowledgedAt) AS firstAt')
            ->andWhere('ack.fallAlert IN (:alerts)')
            ->setParameter('alerts', array_map(static fn (FallAlert $alert): string => $alert->getId()->toRfc4122(), $alerts))
            ->groupBy('ack.fallAlert')
            ->getQuery()
            ->getArrayResult();

        $summary = [];

        foreach ($rows as $row) {
            if (null === $row['firstAt']) {
                continue;
            }

            $alertId = $row['alertId'] instanceof Uuid ? $row['alertId'] : Uuid::fromString((string) $row['alertId']);
            $summary[$alertId->toRfc4122()] = [
                'count' => (int) $row['ackCount'],
                'firstAcknowledgedAt' => new DateTimeImmutable($row['firstAt'], new DateTimeZone('UTC')),
            ];
        }

        return $summary;
    }

    public function save(AlertAcknowledgement $ack): void
    {
        $this->getEntityManager()->persist($ack);
        $this->getEntityManager()->flush();
    }
}
