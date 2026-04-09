<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

final class Version20260409120000 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Creates device, contact, alert, and SMS attempt tables';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE devices (id UUID NOT NULL, public_id VARCHAR(36) NOT NULL, token_hash VARCHAR(64) NOT NULL, platform VARCHAR(16) NOT NULL, app_version VARCHAR(32) NOT NULL, revoked BOOLEAN NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, updated_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, last_seen_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_devices_public_id ON devices (public_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_devices_token_hash ON devices (token_hash)');
        $this->addSql('CREATE TABLE emergency_contacts (id UUID NOT NULL, device_id UUID NOT NULL, name VARCHAR(100) NOT NULL, phone_ciphertext TEXT NOT NULL, phone_hash VARCHAR(64) NOT NULL, phone_last4 VARCHAR(4) NOT NULL, position INT NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, updated_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE INDEX idx_contacts_device ON emergency_contacts (device_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_contacts_device_hash ON emergency_contacts (device_id, phone_hash)');
        $this->addSql('ALTER TABLE emergency_contacts ADD CONSTRAINT FK_CONTACTS_DEVICE FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('CREATE TABLE fall_alerts (id UUID NOT NULL, device_id UUID NOT NULL, client_alert_id VARCHAR(100) NOT NULL, fall_detected_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, received_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, status VARCHAR(32) NOT NULL, locale VARCHAR(8) NOT NULL, latitude DOUBLE PRECISION DEFAULT NULL, longitude DOUBLE PRECISION DEFAULT NULL, cancelled_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE INDEX idx_alerts_device ON fall_alerts (device_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_alerts_device_client ON fall_alerts (device_id, client_alert_id)');
        $this->addSql('ALTER TABLE fall_alerts ADD CONSTRAINT FK_ALERTS_DEVICE FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('CREATE TABLE sms_attempts (id UUID NOT NULL, fall_alert_id UUID NOT NULL, contact_id UUID NOT NULL, provider VARCHAR(32) NOT NULL, provider_message_id VARCHAR(255) DEFAULT NULL, status VARCHAR(32) NOT NULL, error_code VARCHAR(255) DEFAULT NULL, error_message TEXT DEFAULT NULL, retry_count INT NOT NULL, queued_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, sent_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, delivered_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE INDEX idx_sms_attempts_alert ON sms_attempts (fall_alert_id)');
        $this->addSql('CREATE INDEX idx_sms_attempts_contact ON sms_attempts (contact_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_sms_provider_message ON sms_attempts (provider_message_id)');
        $this->addSql('ALTER TABLE sms_attempts ADD CONSTRAINT FK_SMS_ALERT FOREIGN KEY (fall_alert_id) REFERENCES fall_alerts (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('ALTER TABLE sms_attempts ADD CONSTRAINT FK_SMS_CONTACT FOREIGN KEY (contact_id) REFERENCES emergency_contacts (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE sms_attempts');
        $this->addSql('DROP TABLE fall_alerts');
        $this->addSql('DROP TABLE emergency_contacts');
        $this->addSql('DROP TABLE devices');
    }
}
