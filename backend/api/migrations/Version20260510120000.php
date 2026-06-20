<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260510120000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Remove legacy caregiver delivery tables';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('DROP TABLE IF EXISTS sms_attempts');
        $this->addSql('DROP TABLE IF EXISTS emergency_contacts');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('SELECT 1');
    }
}
