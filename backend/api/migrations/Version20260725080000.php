<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260725080000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add revision, detection source, and resolution to fall alert incidents';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('ALTER TABLE fall_alerts ADD revision INT DEFAULT 1 NOT NULL');
        $this->addSql("ALTER TABLE fall_alerts ADD detection_source VARCHAR(32) DEFAULT 'assisted_phone' NOT NULL");
        $this->addSql("ALTER TABLE fall_alerts ADD resolution VARCHAR(32) DEFAULT 'unknown' NOT NULL");
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE fall_alerts DROP revision');
        $this->addSql('ALTER TABLE fall_alerts DROP detection_source');
        $this->addSql('ALTER TABLE fall_alerts DROP resolution');
    }
}
