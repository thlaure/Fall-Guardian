<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260725100000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add short-lived one-time companion device enrollments';
    }

    #[Override]
    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE companion_enrollments (id UUID NOT NULL, protected_person_id UUID NOT NULL, created_by_device_id UUID NOT NULL, token_hash VARCHAR(64) NOT NULL, platform VARCHAR(16) NOT NULL, expires_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, claimed_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL, PRIMARY KEY(id))');
        $this->addSql('CREATE UNIQUE INDEX uniq_companion_enrollment_token ON companion_enrollments (token_hash)');
        $this->addSql('CREATE INDEX idx_companion_enrollment_person ON companion_enrollments (protected_person_id)');
        $this->addSql('CREATE INDEX idx_companion_enrollment_creator ON companion_enrollments (created_by_device_id)');
        $this->addSql('ALTER TABLE companion_enrollments ADD CONSTRAINT FK_COMPANION_ENROLLMENT_PERSON FOREIGN KEY (protected_person_id) REFERENCES protected_persons (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
        $this->addSql('ALTER TABLE companion_enrollments ADD CONSTRAINT FK_COMPANION_ENROLLMENT_CREATOR FOREIGN KEY (created_by_device_id) REFERENCES devices (id) ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE companion_enrollments');
    }
}
