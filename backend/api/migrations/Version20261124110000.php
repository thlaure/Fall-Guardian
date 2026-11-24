<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

/**
 * Indexes supporting the time-boxed retention purge (fall_alerts.received_at
 * cutoff scans, stale rate-limit buckets).
 *
 * Built CONCURRENTLY so writes are never blocked; each index is dropped first
 * because an interrupted concurrent build leaves an INVALID index that
 * `IF NOT EXISTS` would keep.
 */
final class Version20261124110000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add indexes for the data-retention purge';
    }

    #[Override]
    public function isTransactional(): bool
    {
        return false;
    }

    #[Override]
    public function up(Schema $schema): void
    {
        $this->addSql("SET lock_timeout = '5s'");
        $this->addSql('DROP INDEX CONCURRENTLY IF EXISTS idx_fall_alerts_received_at');
        $this->addSql('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_fall_alerts_received_at ON fall_alerts (received_at)');
        $this->addSql('DROP INDEX CONCURRENTLY IF EXISTS idx_rate_limit_buckets_window_start');
        $this->addSql('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rate_limit_buckets_window_start ON rate_limit_buckets (window_start_at)');
        $this->addSql('RESET lock_timeout');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP INDEX IF EXISTS idx_rate_limit_buckets_window_start');
        $this->addSql('DROP INDEX IF EXISTS idx_fall_alerts_received_at');
    }
}
