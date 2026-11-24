<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

/**
 * Alert delivery hardening: dispatch retries, reminders, per-round push
 * attempts, hashed invite codes and service heartbeats.
 *
 * Safe on a populated database:
 *  - only additive changes (nullable columns or constant defaults, which are
 *    metadata-only in PostgreSQL 11+), plus dropping NOT NULL on a column;
 *  - no table rewrite and no backfill UPDATE;
 *  - indexes are built CONCURRENTLY, so writes are never blocked; each is
 *    dropped first, because a CONCURRENTLY build interrupted by lock_timeout
 *    leaves an INVALID index that `IF NOT EXISTS` would silently keep;
 *  - a short lock_timeout makes the brief ACCESS EXCLUSIVE locks of ALTER
 *    TABLE fail fast instead of queueing behind long transactions;
 *  - every statement is idempotent so a failed run can simply be re-run.
 *
 * Existing failed/partially-sent alerts keep next_dispatch_retry_at = NULL and
 * are therefore never retried; already-issued plaintext invites stay
 * redeemable through the legacy lookup until they expire (30 minutes).
 */
final class Version20261121120000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add dispatch retry/reminder tracking, push attempt rounds, hashed invite codes and service heartbeats';
    }

    #[Override]
    public function isTransactional(): bool
    {
        // CREATE INDEX CONCURRENTLY cannot run inside a transaction.
        return false;
    }

    #[Override]
    public function up(Schema $schema): void
    {
        $this->addSql("SET lock_timeout = '5s'");

        $this->addSql('ALTER TABLE fall_alerts ADD COLUMN IF NOT EXISTS dispatch_attempts INT DEFAULT 0 NOT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD COLUMN IF NOT EXISTS next_dispatch_retry_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD COLUMN IF NOT EXISTS reminder_count INT DEFAULT 0 NOT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD COLUMN IF NOT EXISTS last_reminder_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql('DROP INDEX CONCURRENTLY IF EXISTS idx_fall_alerts_retry_due');
        $this->addSql('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_fall_alerts_retry_due ON fall_alerts (status, next_dispatch_retry_at)');
        $this->addSql('DROP INDEX CONCURRENTLY IF EXISTS idx_fall_alerts_ack_due');
        $this->addSql('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_fall_alerts_ack_due ON fall_alerts (status, acknowledgement_deadline_at)');

        $this->addSql('ALTER TABLE push_attempts ADD COLUMN IF NOT EXISTS reminder_number INT DEFAULT 0 NOT NULL');
        $this->addSql('DROP INDEX CONCURRENTLY IF EXISTS idx_push_attempts_alert_round');
        $this->addSql('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_push_attempts_alert_round ON push_attempts (fall_alert_id, reminder_number, status)');

        $this->addSql('ALTER TABLE caregiver_invites ADD COLUMN IF NOT EXISTS code_hash VARCHAR(64) DEFAULT NULL');
        $this->addSql('ALTER TABLE caregiver_invites ALTER code DROP NOT NULL');
        $this->addSql('DROP INDEX CONCURRENTLY IF EXISTS uniq_caregiver_invites_code_hash');
        $this->addSql('CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uniq_caregiver_invites_code_hash ON caregiver_invites (code_hash)');

        $this->addSql('CREATE TABLE IF NOT EXISTS service_heartbeats (name VARCHAR(64) NOT NULL, beat_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY(name))');

        $this->addSql('RESET lock_timeout');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE IF EXISTS service_heartbeats');

        // Hashed invites cannot be represented without a plaintext code; they
        // are short-lived (30 minutes), so dropping them is acceptable.
        $this->addSql('DELETE FROM caregiver_invites WHERE code IS NULL');
        $this->addSql('DROP INDEX IF EXISTS uniq_caregiver_invites_code_hash');
        $this->addSql('ALTER TABLE caregiver_invites ALTER code SET NOT NULL');
        $this->addSql('ALTER TABLE caregiver_invites DROP COLUMN IF EXISTS code_hash');

        $this->addSql('DROP INDEX IF EXISTS idx_push_attempts_alert_round');
        $this->addSql('ALTER TABLE push_attempts DROP COLUMN IF EXISTS reminder_number');

        $this->addSql('DROP INDEX IF EXISTS idx_fall_alerts_ack_due');
        $this->addSql('DROP INDEX IF EXISTS idx_fall_alerts_retry_due');
        $this->addSql('ALTER TABLE fall_alerts DROP COLUMN IF EXISTS last_reminder_at');
        $this->addSql('ALTER TABLE fall_alerts DROP COLUMN IF EXISTS reminder_count');
        $this->addSql('ALTER TABLE fall_alerts DROP COLUMN IF EXISTS next_dispatch_retry_at');
        $this->addSql('ALTER TABLE fall_alerts DROP COLUMN IF EXISTS dispatch_attempts');
    }
}
