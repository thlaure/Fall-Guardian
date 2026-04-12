<?php

declare(strict_types=1);

namespace App\Application\Alert\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\UI\State\CancelFallAlertProcessor;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{clientAlertId}/cancel',
        output: FallAlertView::class,
        read: false,
        deserialize: false,
        processor: CancelFallAlertProcessor::class,
    ),
])]
final class CancelFallAlertInput
{
}
