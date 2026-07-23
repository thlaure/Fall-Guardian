<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;
use Override;

final class Version20260723080000 extends AbstractMigration
{
    #[Override]
    public function getDescription(): string
    {
        return 'Add backend-owned fall alert deadlines, dispatch claims, and delivery receipts';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('ALTER TABLE fall_alerts ADD cancel_deadline_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD dispatch_claimed_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD delivery_receipt_deadline_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD first_delivery_receipt_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql('ALTER TABLE fall_alerts ADD acknowledgement_deadline_at TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NULL');
        $this->addSql("UPDATE fall_alerts SET cancel_deadline_at = received_at + INTERVAL '30 seconds'");
        $this->addSql('ALTER TABLE fall_alerts ALTER cancel_deadline_at SET NOT NULL');
        $this->addSql('CREATE INDEX idx_fall_alerts_dispatch_due ON fall_alerts (status, cancel_deadline_at, dispatch_claimed_at)');
    }

    #[Override]
    public function down(Schema $schema): void
    {
        $this->addSql('DROP INDEX idx_fall_alerts_dispatch_due');
        $this->addSql('ALTER TABLE fall_alerts DROP cancel_deadline_at');
        $this->addSql('ALTER TABLE fall_alerts DROP dispatch_claimed_at');
        $this->addSql('ALTER TABLE fall_alerts DROP delivery_receipt_deadline_at');
        $this->addSql('ALTER TABLE fall_alerts DROP first_delivery_receipt_at');
        $this->addSql('ALTER TABLE fall_alerts DROP acknowledgement_deadline_at');
    }
}
