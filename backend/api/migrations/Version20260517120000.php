<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260517120000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add endpoint rate limit buckets';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('ALTER TABLE caregiver_invites ALTER code TYPE VARCHAR(32)');
        $this->addSql('CREATE TABLE rate_limit_buckets (id VARCHAR(64) NOT NULL, window_start_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, hits INT NOT NULL, PRIMARY KEY(id))');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE rate_limit_buckets');
        $this->addSql('ALTER TABLE caregiver_invites ALTER code TYPE VARCHAR(8)');
    }
}
