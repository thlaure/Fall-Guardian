<?php

declare(strict_types=1);

namespace App\Controller;

use App\Infrastructure\Sms\FakeSmsStore;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Routing\Attribute\Route;

final class DebugFakeSmsController
{
    public function __construct(
        private readonly FakeSmsStore $store,
        private readonly string $appEnv,
    ) {
    }

    #[Route('/debug/fake-sms', name: 'app_debug_fake_sms', methods: ['GET'])]
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
