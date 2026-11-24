<?php

declare(strict_types=1);

namespace App\Domain\Healthcheck\Controller;

use App\Domain\Healthcheck\Service\ReadinessChecker;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final readonly class HealthController
{
    public function __construct(private ReadinessChecker $readinessChecker)
    {
    }

    /** Liveness: the HTTP process answers. Intentionally dependency-free. */
    #[Route('/health', name: 'app_health', methods: [Request::METHOD_GET])]
    public function __invoke(): JsonResponse
    {
        return new JsonResponse([
            'status' => 'ok',
            'service' => 'fall-guardian-backend',
        ]);
    }

    /** Readiness: fall escalation can actually happen (database, backlog, reconciler). */
    #[Route('/health/ready', name: 'app_health_ready', methods: [Request::METHOD_GET])]
    public function ready(): JsonResponse
    {
        $result = $this->readinessChecker->check();

        return new JsonResponse(
            [
                'status' => $result['ready'] ? 'ok' : 'unavailable',
                'service' => 'fall-guardian-backend',
                'checks' => $result['checks'],
            ],
            $result['ready'] ? Response::HTTP_OK : Response::HTTP_SERVICE_UNAVAILABLE,
            ['Cache-Control' => 'no-store'],
        );
    }
}
