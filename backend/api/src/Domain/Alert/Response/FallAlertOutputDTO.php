<?php

declare(strict_types=1);

namespace App\Domain\Alert\Response;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Alert\Provider\FallAlertProvider;
use App\Entity\FallAlert;
use App\Shared\DateTime\ApiDateTimeFormatter;

#[ApiResource(operations: [
    new Get(
        uriTemplate: '/api/v1/fall-alerts/{id}',
        openapi: new Operation(
            tags: ['Fall alerts'],
            summary: 'Get a fall alert status',
            description: 'Returns the current lifecycle status of an alert reported by the authenticated protected-person device.',
            security: [['deviceBearer' => []]],
        ),
        provider: FallAlertProvider::class,
    ),
])]
final class FallAlertOutputDTO
{
    public function __construct(
        public string $id,
        public string $clientAlertId,
        public string $status,
        public string $fallTimestamp,
        public string $receivedAt,
        public string $cancelDeadlineAt,
        public ?string $cancelledAt,
        public ?string $dispatchClaimedAt,
        public ?string $deliveryReceiptDeadlineAt,
        public ?string $firstDeliveryReceiptAt,
        public ?string $acknowledgementDeadlineAt,
    ) {
    }

    public static function fromEntity(FallAlert $alert): self
    {
        return new self(
            $alert->getId()->toRfc4122(),
            $alert->getClientAlertId(),
            $alert->getStatus()->value,
            ApiDateTimeFormatter::formatUtc($alert->getFallDetectedAt()),
            ApiDateTimeFormatter::formatUtc($alert->getReceivedAt()),
            ApiDateTimeFormatter::formatUtc($alert->getCancelDeadlineAt()),
            null === $alert->getCancelledAt() ? null : ApiDateTimeFormatter::formatUtc($alert->getCancelledAt()),
            null === $alert->getDispatchClaimedAt() ? null : ApiDateTimeFormatter::formatUtc($alert->getDispatchClaimedAt()),
            null === $alert->getDeliveryReceiptDeadlineAt() ? null : ApiDateTimeFormatter::formatUtc($alert->getDeliveryReceiptDeadlineAt()),
            null === $alert->getFirstDeliveryReceiptAt() ? null : ApiDateTimeFormatter::formatUtc($alert->getFirstDeliveryReceiptAt()),
            null === $alert->getAcknowledgementDeadlineAt() ? null : ApiDateTimeFormatter::formatUtc($alert->getAcknowledgementDeadlineAt()),
        );
    }
}
