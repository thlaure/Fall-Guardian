<?php

declare(strict_types=1);

namespace App\Security;

use App\Repository\DeviceRepository;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Exception\AuthenticationException;
use Symfony\Component\Security\Http\Authenticator\AbstractAuthenticator;
use Symfony\Component\Security\Http\Authenticator\Passport\Badge\UserBadge;
use Symfony\Component\Security\Http\Authenticator\Passport\SelfValidatingPassport;

final class DeviceTokenAuthenticator extends AbstractAuthenticator
{
    public function __construct(
        private readonly DeviceRepository $deviceRepository,
        private readonly DeviceTokenHasher $tokenHasher,
    ) {
    }

    public function supports(Request $request): bool
    {
        if (!str_starts_with($request->getPathInfo(), '/api/v1/')) {
            return false;
        }

        return $request->getPathInfo() !== '/api/v1/devices/register';
    }

    public function authenticate(Request $request): SelfValidatingPassport
    {
        $header = (string) $request->headers->get('Authorization', '');

        if (!preg_match('/^Bearer\s+(?<token>.+)$/i', $header, $matches)) {
            throw new AuthenticationException('Missing bearer token.');
        }

        $hashedToken = $this->tokenHasher->hash($matches['token']);

        return new SelfValidatingPassport(new UserBadge($hashedToken, function (string $userIdentifier): DeviceApiUser {
            $device = $this->deviceRepository->findActiveByTokenHash($userIdentifier);

            if (null === $device) {
                throw new AuthenticationException('Invalid device token.');
            }

            $device->touchSeenAt();

            return new DeviceApiUser($device);
        }));
    }

    public function onAuthenticationSuccess(Request $request, TokenInterface $token, string $firewallName): ?Response
    {
        return null;
    }

    public function onAuthenticationFailure(Request $request, AuthenticationException $exception): Response
    {
        return new JsonResponse([
            'error' => 'unauthorized',
            'message' => $exception->getMessageKey(),
        ], Response::HTTP_UNAUTHORIZED);
    }
}
