<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Retention\Port\RetentionRepositoryInterface;
use App\Enum\FallAlertStatus;
use DateTimeImmutable;
use Doctrine\DBAL\ArrayParameterType;
use Doctrine\DBAL\Connection;
use Doctrine\DBAL\Types\Types;

/**
 * Bounded batch deletes: every statement touches at most `$batchSize` rows so
 * retention never holds long locks on hot tables.
 */
final readonly class DoctrineRetentionRepository implements RetentionRepositoryInterface
{
    public function __construct(private Connection $connection)
    {
    }

    public function deleteClosedAlertsBefore(DateTimeImmutable $cutoff, int $batchSize): int
    {
        return $this->connection->transactional(static function (Connection $connection) use ($cutoff, $batchSize): int {
            /** @var list<string> $ids */
            $ids = $connection->fetchFirstColumn(
                sprintf('SELECT id FROM fall_alerts WHERE (%s) AND received_at < :cutoff ORDER BY received_at LIMIT %d FOR UPDATE SKIP LOCKED', self::closedCondition(), $batchSize),
                ['cutoff' => $cutoff],
                ['cutoff' => Types::DATETIME_IMMUTABLE],
            );

            if ([] === $ids) {
                return 0;
            }

            $parameters = ['ids' => $ids];
            $types = ['ids' => ArrayParameterType::STRING];
            $connection->executeStatement('DELETE FROM push_attempts WHERE fall_alert_id IN (:ids)', $parameters, $types);
            $connection->executeStatement('DELETE FROM alert_acknowledgements WHERE fall_alert_id IN (:ids)', $parameters, $types);

            return (int) $connection->executeStatement('DELETE FROM fall_alerts WHERE id IN (:ids)', $parameters, $types);
        });
    }

    public function eraseLocationOfClosedAlertsBefore(DateTimeImmutable $cutoff, int $batchSize): int
    {
        return (int) $this->connection->executeStatement(
            sprintf(
                'UPDATE fall_alerts SET latitude = NULL, longitude = NULL WHERE id IN ('
                .'SELECT id FROM fall_alerts WHERE (%s) AND received_at < :cutoff'
                .' AND (latitude IS NOT NULL OR longitude IS NOT NULL) LIMIT %d)',
                self::closedCondition(),
                $batchSize,
            ),
            ['cutoff' => $cutoff],
            ['cutoff' => Types::DATETIME_IMMUTABLE],
        );
    }

    public function deleteFinishedInvitesBefore(DateTimeImmutable $cutoff, int $batchSize): int
    {
        return (int) $this->connection->executeStatement(
            sprintf('DELETE FROM caregiver_invites WHERE id IN (SELECT id FROM caregiver_invites WHERE used_at < :cutoff OR expires_at < :cutoff LIMIT %d)', $batchSize),
            ['cutoff' => $cutoff],
            ['cutoff' => Types::DATETIME_IMMUTABLE],
        );
    }

    public function deleteFinishedCompanionEnrollmentsBefore(DateTimeImmutable $cutoff, int $batchSize): int
    {
        return (int) $this->connection->executeStatement(
            sprintf('DELETE FROM companion_enrollments WHERE id IN (SELECT id FROM companion_enrollments WHERE claimed_at < :cutoff OR expires_at < :cutoff LIMIT %d)', $batchSize),
            ['cutoff' => $cutoff],
            ['cutoff' => Types::DATETIME_IMMUTABLE],
        );
    }

    public function deleteRateLimitBucketsBefore(DateTimeImmutable $cutoff, int $batchSize): int
    {
        return (int) $this->connection->executeStatement(
            sprintf('DELETE FROM rate_limit_buckets WHERE id IN (SELECT id FROM rate_limit_buckets WHERE window_start_at < :cutoff LIMIT %d)', $batchSize),
            ['cutoff' => $cutoff],
            ['cutoff' => Types::DATETIME_IMMUTABLE],
        );
    }

    /**
     * Alerts in these states no longer drive any escalation. Failed and
     * partially-sent alerts count only once no retry is scheduled.
     */
    private static function closedCondition(): string
    {
        return sprintf(
            "status IN ('%s', '%s', '%s') OR (status IN ('%s', '%s') AND next_dispatch_retry_at IS NULL)",
            FallAlertStatus::Sent->value,
            FallAlertStatus::Acknowledged->value,
            FallAlertStatus::Cancelled->value,
            FallAlertStatus::Failed->value,
            FallAlertStatus::PartiallySent->value,
        );
    }
}
