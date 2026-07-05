<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260704110000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add caregiver-defined protected person names';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('ALTER TABLE caregiver_links ADD protected_person_name VARCHAR(120) DEFAULT NULL');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE caregiver_links DROP protected_person_name');
    }
}
