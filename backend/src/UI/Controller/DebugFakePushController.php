<?php

declare(strict_types=1);

namespace App\UI\Controller;

use App\Infrastructure\Push\FakePushStore;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Routing\Attribute\Route;

final readonly class DebugFakePushController
{
    public function __construct(
        private FakePushStore $store,
        private string $appEnv,
    ) {
    }

    #[Route('/debug/fake-push', name: 'app_debug_fake_push', methods: ['GET'])]
    public function __invoke(): JsonResponse
    {
        if ('prod' === $this->appEnv) {
            throw new NotFoundHttpException();
        }

        return new JsonResponse([
            'provider' => 'fake',
            'messages' => $this->store->all(),
        ]);
    }
}
