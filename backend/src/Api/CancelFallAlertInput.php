<?php

declare(strict_types=1);

namespace App\Api;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\State\CancelFallAlertProcessor;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{clientAlertId}/cancel',
        output: FallAlertView::class,
        processor: CancelFallAlertProcessor::class,
        read: false,
        deserialize: false,
    ),
])]
final class CancelFallAlertInput
{
}
