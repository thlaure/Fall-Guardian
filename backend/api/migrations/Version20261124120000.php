<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

/**
 * Track which reserved reminder numbers were actually handed to the queue, so
 * a reservation whose enqueue failed is retried with the same number.
 *
 * Additive (constant default, metadata-only). Reservations made before this
 * column existed are treated as already enqueued, so nothing is re-sent; the
 * backfill only touches the few alerts that ever got a reminder.
 */
final class Version20261124120000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add fall_alerts.reminder_enqueued_count';
    }

    #[Override]
    public function up(Schema $schema): void
    {
        $this->addSql("SET lock_timeout = '5s'");
        $this->addSql('ALTER TABLE fall_alerts ADD COLUMN IF NOT EXISTS reminder_enqueued_count INT DEFAULT 0 NOT NULL');
        $this->addSql('UPDATE fall_alerts SET reminder_enqueued_count = reminder_count WHERE reminder_count > reminder_enqueued_count');
        $this->addSql('RESET lock_timeout');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE fall_alerts DROP COLUMN IF EXISTS reminder_enqueued_count');
    }
}
