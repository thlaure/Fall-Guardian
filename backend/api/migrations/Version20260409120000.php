<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260409120000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Creates device and alert tables';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE devices (id UUID NOT NULL, public_id VARCHAR(36) NOT NULL, token_hash VARCHAR(64) NOT NULL, platform VARCHAR(16) NOT NULL, app_version VARCHAR(32) NOT NULL, revoked BOOLEAN NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, updated_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, last_seen_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_devices_public_id ON devices (public_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_devices_token_hash ON devices (token_hash)');
        $this->addSql('CREATE TABLE fall_alerts (id UUID NOT NULL, device_id UUID NOT NULL, client_alert_id VARCHAR(100) NOT NULL, fall_detected_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, received_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, status VARCHAR(32) NOT NULL, locale VARCHAR(8) NOT NULL, latitude DOUBLE PRECISION DEFAULT NULL, longitude DOUBLE PRECISION DEFAULT NULL, cancelled_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE INDEX idx_alerts_device ON fall_alerts (device_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_alerts_device_client ON fall_alerts (device_id, client_alert_id)');
        $this->addSql('ALTER TABLE fall_alerts ADD CONSTRAINT FK_ALERTS_DEVICE FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE fall_alerts');
        $this->addSql('DROP TABLE devices');
    }
}
