<?php

declare(strict_types=1);

namespace App\Domain\Caregiver\Request;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use ApiPlatform\OpenApi\Model\Operation;
use App\Domain\Caregiver\Processor\ReportAlertReceiptProcessor;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{id}/receipt',
        input: false,
        output: false,
        read: false,
        openapi: new Operation(
            tags: ['Caregiver alerts'],
            summary: 'Report receipt of a fall alert',
            description: 'Records that a linked caregiver device received a dispatched fall alert. Repeated receipts are idempotent.',
            security: [['deviceBearer' => []]],
        ),
        processor: ReportAlertReceiptProcessor::class,
    ),
])]
final class ReportAlertReceiptInputDTO
{
}
