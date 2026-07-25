<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260725090000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Introduce stable protected-person identity for cross-device incidents';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE protected_persons (id UUID NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY(id))');
        $this->addSql('ALTER TABLE devices ADD protected_person_id UUID DEFAULT NULL');
        $this->addSql("INSERT INTO protected_persons (id, created_at) SELECT id, created_at FROM devices WHERE device_type = 'protected_person'");
        $this->addSql("UPDATE devices SET protected_person_id = id WHERE device_type = 'protected_person'");
        $this->addSql('CREATE INDEX idx_devices_protected_person ON devices (protected_person_id)');
        $this->addSql('ALTER TABLE devices ADD CONSTRAINT FK_DEVICES_PROTECTED_PERSON FOREIGN KEY (protected_person_id) REFERENCES protected_persons (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');

        $this->addSql('ALTER TABLE fall_alerts ADD protected_person_id UUID DEFAULT NULL');
        $this->addSql('UPDATE fall_alerts alert SET protected_person_id = device.protected_person_id FROM devices device WHERE alert.device_id = device.id');
        $this->addSql('CREATE INDEX idx_fall_alerts_protected_person ON fall_alerts (protected_person_id)');
        $this->addSql('CREATE UNIQUE INDEX uniq_alerts_person_client ON fall_alerts (protected_person_id, client_alert_id)');
        $this->addSql('ALTER TABLE fall_alerts ADD CONSTRAINT FK_ALERTS_PROTECTED_PERSON FOREIGN KEY (protected_person_id) REFERENCES protected_persons (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE fall_alerts DROP CONSTRAINT FK_ALERTS_PROTECTED_PERSON');
        $this->addSql('DROP INDEX uniq_alerts_person_client');
        $this->addSql('DROP INDEX idx_fall_alerts_protected_person');
        $this->addSql('ALTER TABLE fall_alerts DROP protected_person_id');
        $this->addSql('ALTER TABLE devices DROP CONSTRAINT FK_DEVICES_PROTECTED_PERSON');
        $this->addSql('DROP INDEX idx_devices_protected_person');
        $this->addSql('ALTER TABLE devices DROP protected_person_id');
        $this->addSql('DROP TABLE protected_persons');
    }
}
