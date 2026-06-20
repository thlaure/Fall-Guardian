# Code & Test Patterns

These are patterns, not rigid templates. Match the surrounding domain before introducing a new structure.

## Design Heuristics

- Prefer explicit, readable code over clever abstractions
- Keep one clear responsibility per class or helper
- Keep framework and persistence details at the edges
- Prefer small typed objects when they clarify data flow better than arrays
- Open extension points only when real variation exists
- Do not force a pure architecture into a local module; improve the design without fighting the surrounding code

---

## State Processor (API Platform Write)

```php
<?php

declare(strict_types=1);

namespace App\Domain\Alert\Processor;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Alert\Handler\CreateFallAlertHandler;
use App\Domain\Alert\Request\CreateFallAlertInputDTO;
use App\Domain\Alert\Response\FallAlertOutputDTO;

final readonly class CreateFallAlertProcessor implements ProcessorInterface
{
    public function __construct(
        private CreateFallAlertHandler $handler,
    ) {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        assert($data instanceof CreateFallAlertInputDTO);

        return ($this->handler)($data);
    }
}
```

---

## Handler

```php
<?php

declare(strict_types=1);

namespace App\Domain\Alert\Handler;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Domain\Alert\Request\CreateFallAlertInputDTO;
use App\Domain\Alert\Response\FallAlertOutputDTO;

final readonly class CreateFallAlertHandler
{
    public function __construct(
        private FallAlertRepositoryInterface $repository,
    ) {
    }

    public function __invoke(CreateFallAlertInputDTO $input): FallAlertOutputDTO
    {
        // business orchestration here
    }
}
```

---

## Port Interface

```php
<?php

declare(strict_types=1);

namespace App\Domain\Alert\Port;

use App\Entity\FallAlert;

interface FallAlertRepositoryInterface
{
    public function find(string $id): FallAlert;

    public function save(FallAlert $entity, bool $flush = true): void;
}
```

---

## Infrastructure Repository

```php
<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Alert\Port\FallAlertRepositoryInterface;
use App\Entity\FallAlert;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

final class DoctrineFallAlertRepository extends ServiceEntityRepository implements FallAlertRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, FallAlert::class);
    }

    public function find(mixed $id, mixed $lockMode = null, mixed $lockVersion = null): FallAlert
    {
        $entity = parent::find($id);

        if (null === $entity) {
            throw new FallAlertNotFoundException();
        }

        return $entity;
    }

    public function save(FallAlert $entity, bool $flush = true): void
    {
        $this->getEntityManager()->persist($entity);

        if ($flush) {
            $this->getEntityManager()->flush();
        }
    }
}
```

Bind in `config/services.yaml`:

```yaml
App\Domain\Alert\Port\FallAlertRepositoryInterface:
    class: App\Infrastructure\Persistence\DoctrineFallAlertRepository
```

---

## Input DTO (API Platform ApiResource + Validation)

```php
<?php

declare(strict_types=1);

namespace App\Domain\Alert\Request;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class CreateFallAlertInputDTO
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Uuid]
        public string $deviceId,

        #[Assert\NotNull]
        public \DateTimeInterface $detectedAt,
    ) {
    }
}
```

---

## Messenger Message + Handler

```php
// Message — data container only
final readonly class SendFallAlertPushMessage
{
    public function __construct(
        public string $alertId,
    ) {
    }
}

// Handler — thin orchestrator
final class SendFallAlertPushMessageHandler
{
    public function __construct(
        private FallAlertRepositoryInterface $alertRepository,
        private PushGatewayInterface $pushGateway,
    ) {
    }

    public function __invoke(SendFallAlertPushMessage $message): void
    {
        $alert = $this->alertRepository->find($message->alertId);
        $this->pushGateway->send($alert);
    }
}
```

---

## Domain Service (pure, stateless)

Location: `src/Domain/{Feature}/Service/{Rule}Service.php`
Test: `tests/Unit/Domain/{Feature}/Service/{Rule}ServiceTest.php`

Rules:
- No infrastructure dependencies — receive already-resolved values as parameters
- No Port calls — services receive values, not entities fetched from repositories
- Single responsibility — one rule, one class
- Descriptive name: `AlertEscalationResolver`, `PushTokenValidator` — never generic suffixes
- `final readonly` unless framework constraints prevent it
- Stateless — all inputs through method parameters

```php
final readonly class AlertEscalationResolver
{
    public function shouldEscalate(string $status, \DateTimeInterface $detectedAt): bool
    {
        // pure domain rule — no I/O, no side effects
    }
}
```

Unit test for a pure service — no mocks needed, pass concrete values:

```php
final class AlertEscalationResolverTest extends TestCase
{
    private AlertEscalationResolver $service;

    protected function setUp(): void
    {
        $this->service = new AlertEscalationResolver();
    }

    public function testShouldEscalateWithActiveStatusReturnsTrue(): void
    {
        $this->assertTrue($this->service->shouldEscalate('active', new \DateTimeImmutable('-5 minutes')));
    }
}
```

---

## Custom Exception

```php
final class FallAlertNotFoundException extends HttpException
{
    public function __construct(string $message = 'Fall alert not found')
    {
        parent::__construct(Response::HTTP_NOT_FOUND, $message);
    }
}
```

---

## Unit Test Pattern

```php
final class CreateFallAlertHandlerTest extends TestCase
{
    private FallAlertRepositoryInterface&MockObject $repository;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(FallAlertRepositoryInterface::class);
    }

    public function testInvokeWithValidInputCreatesAlert(): void
    {
        $this->repository->expects($this->once())->method('save');

        $handler = new CreateFallAlertHandler($this->repository);
        $result = $handler(new CreateFallAlertInputDTO('uuid-here', new \DateTimeImmutable()));

        $this->assertNotNull($result);
    }

    public function testInvokeWithUnknownAlertThrowsNotFoundException(): void
    {
        $this->repository->method('find')->willThrowException(new FallAlertNotFoundException());

        $this->expectException(FallAlertNotFoundException::class);

        (new GetFallAlertHandler($this->repository))(new GetFallAlertQuery('unknown-id'));
    }
}
```

### Always mock the **Port interface**, never the concrete Doctrine repository
### Name: `test{Method}{Scenario}{Expected}`
### Add Behat coverage when HTTP behavior needs end-to-end verification
