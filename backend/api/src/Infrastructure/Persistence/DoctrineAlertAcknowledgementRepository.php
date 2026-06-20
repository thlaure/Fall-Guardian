<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\AlertAcknowledgementRepositoryInterface;
use App\Entity\AlertAcknowledgement;
use App\Entity\Device;
use App\Entity\FallAlert;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

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

    public function save(AlertAcknowledgement $ack): void
    {
        $this->getEntityManager()->persist($ack);
        $this->getEntityManager()->flush();
    }
}
