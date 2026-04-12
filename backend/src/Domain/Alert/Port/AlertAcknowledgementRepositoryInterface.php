<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\AlertAcknowledgement;
use App\Entity\Device;
use App\Entity\FallAlert;

interface AlertAcknowledgementRepositoryInterface
{
    public function findByCaregiverAndAlert(FallAlert $alert, Device $caregiverDevice): ?AlertAcknowledgement;

    public function save(AlertAcknowledgement $ack): void;
}
