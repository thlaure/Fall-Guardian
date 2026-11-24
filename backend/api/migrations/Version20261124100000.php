<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

/**
 * Remember the outcome of the last dispatch round so the public alert status
 * stays stable (sent/partially_sent/failed) while a retry round runs.
 *
 * Additive and metadata-only: a nullable column, no backfill (alerts without
 * an outcome keep their current behaviour), short lock_timeout, idempotent.
 */
final class Version20261124100000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add fall_alerts.last_dispatch_outcome';
    }

    #[Override]
    public function up(Schema $schema): void
    {
        $this->addSql("SET lock_timeout = '5s'");
        $this->addSql('ALTER TABLE fall_alerts ADD COLUMN IF NOT EXISTS last_dispatch_outcome VARCHAR(32) DEFAULT NULL');
        $this->addSql('RESET lock_timeout');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE fall_alerts DROP COLUMN IF EXISTS last_dispatch_outcome');
    }
}
