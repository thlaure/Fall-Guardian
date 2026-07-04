<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260704111500 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add caregiver display names to caregiver links';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('ALTER TABLE caregiver_links ADD caregiver_name VARCHAR(120) DEFAULT NULL');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE caregiver_links DROP caregiver_name');
    }
}
