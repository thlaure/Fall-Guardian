<?php

declare(strict_types=1);

namespace App\UI\Controller;

use App\Infrastructure\Sms\FakeSmsStore;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Routing\Attribute\Route;

final readonly class DebugFakeSmsController
{
    public function __construct(
        private FakeSmsStore $store,
        private string $appEnv,
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
