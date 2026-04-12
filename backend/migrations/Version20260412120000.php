<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260412120000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add caregiver model: device_type, caregiver_invites, caregiver_links, caregiver_push_tokens, push_attempts';
    }

    public function up(Schema $schema): void
    {
        // Add device_type to devices table (default protected_person for existing rows)
        $this->addSql("ALTER TABLE devices ADD device_type VARCHAR(32) NOT NULL DEFAULT 'protected_person'");

        // Caregiver invites — short-lived codes emitted by protected-person devices
        $this->addSql('CREATE TABLE caregiver_invites (id UUID NOT NULL, device_id UUID NOT NULL, code VARCHAR(8) NOT NULL, expires_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, used_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_caregiver_invites_code ON caregiver_invites (code)');
        $this->addSql('CREATE INDEX idx_caregiver_invites_device ON caregiver_invites (device_id)');
        $this->addSql('ALTER TABLE caregiver_invites ADD CONSTRAINT FK_CAREGIVER_INVITES_DEVICE FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');

        // Caregiver links — active associations between a protected device and a caregiver device
        $this->addSql('CREATE TABLE caregiver_links (id UUID NOT NULL, protected_device_id UUID NOT NULL, caregiver_device_id UUID NOT NULL, status VARCHAR(32) NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, updated_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_caregiver_links_pair ON caregiver_links (protected_device_id, caregiver_device_id)');
        $this->addSql('CREATE INDEX idx_caregiver_links_protected ON caregiver_links (protected_device_id)');
        $this->addSql('CREATE INDEX idx_caregiver_links_caregiver ON caregiver_links (caregiver_device_id)');
        $this->addSql('ALTER TABLE caregiver_links ADD CONSTRAINT FK_CAREGIVER_LINKS_PROTECTED FOREIGN KEY (protected_device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('ALTER TABLE caregiver_links ADD CONSTRAINT FK_CAREGIVER_LINKS_CAREGIVER FOREIGN KEY (caregiver_device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');

        // Caregiver push tokens — one FCM token per caregiver device
        $this->addSql('CREATE TABLE caregiver_push_tokens (id UUID NOT NULL, device_id UUID NOT NULL, fcm_token TEXT NOT NULL, updated_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_push_tokens_device ON caregiver_push_tokens (device_id)');
        $this->addSql('ALTER TABLE caregiver_push_tokens ADD CONSTRAINT FK_PUSH_TOKENS_DEVICE FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');

        // Push attempts — one row per caregiver notified per alert
        $this->addSql('CREATE TABLE push_attempts (id UUID NOT NULL, fall_alert_id UUID NOT NULL, caregiver_device_id UUID NOT NULL, provider VARCHAR(32) NOT NULL, provider_message_id VARCHAR(255) DEFAULT NULL, status VARCHAR(32) NOT NULL, error_code VARCHAR(255) DEFAULT NULL, error_message TEXT DEFAULT NULL, retry_count INT NOT NULL, queued_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, sent_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE INDEX idx_push_attempts_alert ON push_attempts (fall_alert_id)');
        $this->addSql('CREATE INDEX idx_push_attempts_caregiver ON push_attempts (caregiver_device_id)');
        $this->addSql('ALTER TABLE push_attempts ADD CONSTRAINT FK_PUSH_ATTEMPTS_ALERT FOREIGN KEY (fall_alert_id) REFERENCES fall_alerts (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('ALTER TABLE push_attempts ADD CONSTRAINT FK_PUSH_ATTEMPTS_CAREGIVER FOREIGN KEY (caregiver_device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');

        // Alert acknowledgements — caregiver confirmation that alert was received
        $this->addSql('CREATE TABLE alert_acknowledgements (id UUID NOT NULL, fall_alert_id UUID NOT NULL, caregiver_device_id UUID NOT NULL, acknowledged_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_ack_alert_caregiver ON alert_acknowledgements (fall_alert_id, caregiver_device_id)');
        $this->addSql('CREATE INDEX idx_ack_alert ON alert_acknowledgements (fall_alert_id)');
        $this->addSql('ALTER TABLE alert_acknowledgements ADD CONSTRAINT FK_ACK_ALERT FOREIGN KEY (fall_alert_id) REFERENCES fall_alerts (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('ALTER TABLE alert_acknowledgements ADD CONSTRAINT FK_ACK_CAREGIVER FOREIGN KEY (caregiver_device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE alert_acknowledgements');
        $this->addSql('DROP TABLE push_attempts');
        $this->addSql('DROP TABLE caregiver_push_tokens');
        $this->addSql('DROP TABLE caregiver_links');
        $this->addSql('DROP TABLE caregiver_invites');
        $this->addSql('ALTER TABLE devices DROP COLUMN device_type');
    }
}
