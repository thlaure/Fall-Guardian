# Fall Guardian Patterns

These are patterns, not rigid templates. Match the surrounding domain before introducing a new structure.

## Design Heuristics

- Prefer explicit, readable code over clever abstractions.
- Keep one clear responsibility per class or helper.
- Keep framework and persistence details at the edges when practical.
- Prefer small typed objects when they clarify data flow better than arrays.
- Open extension points only when real variation exists.
- Do not force a pure architecture into a mixed area; improve the design without fighting the surrounding code.
- Use native API Platform, Symfony, Flutter, Android, iOS, Wear OS, or watchOS behavior directly when it solves the need cleanly.

## Backend Domain Layout

New backend business features should live under `backend/src/Domain/<Feature>/...`.

Current folder vocabulary:

- `DTO/`: API input DTOs, output/view DTOs, and small domain data carriers.
- `State/`: API Platform processors/providers.
- `Handler/`: application/business orchestration and Messenger handlers.
- `Message/`: Messenger messages for asynchronous workflows.
- `Port/`: repository/gateway interfaces owned by the domain.
- `Controller/`: thin HTTP controllers when API Platform is not the right entrypoint.

Avoid reintroducing top-level backend `Application/`, `UI/`, or `Message/` directories.

## API Platform Write Resource

```php
<?php

declare(strict_types=1);

namespace App\Domain\Feature\DTO;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use App\Domain\Feature\State\CreateFeatureProcessor;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/features',
        output: FeatureView::class,
        read: false,
        processor: CreateFeatureProcessor::class,
    ),
])]
final class CreateFeatureInput
{
    #[Assert\NotBlank]
    #[Assert\Length(max: 100)]
    public string $name = '';
}
```

Rules:

- Validate external input at the DTO boundary.
- Keep DTOs logic-free.
- Preserve `/api/v1` for backend public routes.

## API Platform Processor

```php
<?php

declare(strict_types=1);

namespace App\Domain\Feature\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Feature\DTO\CreateFeatureInput;
use App\Domain\Feature\DTO\FeatureView;
use App\Domain\Feature\Handler\CreateFeatureHandler;

use function assert;

/**
 * @implements ProcessorInterface<CreateFeatureInput, FeatureView>
 */
final readonly class CreateFeatureProcessor implements ProcessorInterface
{
    public function __construct(private CreateFeatureHandler $handler)
    {
    }

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FeatureView
    {
        assert($data instanceof CreateFeatureInput);

        return FeatureView::fromEntity(($this->handler)($data->name));
    }
}
```

Rules:

- Processors/providers translate API Platform input/output and delegate business decisions.
- Do not put durable workflow logic in processors when a handler/service is the right owner.

## Handler

```php
<?php

declare(strict_types=1);

namespace App\Domain\Feature\Handler;

use App\Domain\Feature\Port\FeatureRepositoryInterface;
use App\Entity\Feature;

final readonly class CreateFeatureHandler
{
    public function __construct(private FeatureRepositoryInterface $repository)
    {
    }

    public function __invoke(string $name): Feature
    {
        $feature = new Feature($name);
        $this->repository->save($feature);

        return $feature;
    }
}
```

Rules:

- Handlers own business/application orchestration.
- Depend on ports when persistence or external delivery is a boundary.
- Keep behavior explicit; avoid hidden work in generic utilities.

## Output View

```php
<?php

declare(strict_types=1);

namespace App\Domain\Feature\DTO;

use App\Entity\Feature;

final readonly class FeatureView
{
    public function __construct(
        public string $id,
        public string $name,
    ) {
    }

    public static function fromEntity(Feature $feature): self
    {
        return new self(
            $feature->getId()->toRfc4122(),
            $feature->getName(),
        );
    }
}
```

Rules:

- Expose only fields intended for clients.
- Keep response/view fields stable and explicit.

## Repository Port

```php
<?php

declare(strict_types=1);

namespace App\Domain\Feature\Port;

use App\Entity\Feature;

interface FeatureRepositoryInterface
{
    public function findById(string $id): ?Feature;

    public function save(Feature $feature): void;
}
```

Rules:

- Repositories own persistence and data access only.
- Domain handlers should not depend on concrete Doctrine repositories.

## Messenger Handler

```php
<?php

declare(strict_types=1);

namespace App\Domain\Feature\Handler;

use App\Domain\Feature\Message\SendFeatureMessage;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final readonly class SendFeatureMessageHandler
{
    public function __invoke(SendFeatureMessage $message): void
    {
        // Load state, apply explicit workflow, persist audit.
    }
}
```

Rules:

- Asynchronous delivery workflows must be idempotent where practical.
- Persist delivery attempts and failures when they affect alert/caregiver auditability.

## Unit Test

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain;

use App\Domain\Feature\Handler\CreateFeatureHandler;
use App\Domain\Feature\Port\FeatureRepositoryInterface;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class CreateFeatureHandlerTest extends TestCase
{
    private FeatureRepositoryInterface&MockObject $repository;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(FeatureRepositoryInterface::class);
    }

    public function testInvokeWithValidNameSavesFeature(): void
    {
        $this->repository->expects($this->once())->method('save');

        $handler = new CreateFeatureHandler($this->repository);
        $feature = $handler('Example');

        self::assertSame('Example', $feature->getName());
    }
}
```

## Flutter Coordinator-Owned Workflow

- `AlertCoordinator` owns protected-person alert lifecycle, timeout, cancel propagation, and escalation.
- Widgets render state and trigger intents; they do not own workflow timers or delivery side effects.
- Repositories own persistence; services/adapters own runtime integrations.

## Native Bridge Pattern

- Native phone/watch code receives platform events.
- Bridges validate and translate platform events into shared app events.
- Platform adapters do not duplicate Flutter/backend workflow decisions.

## Cross-Platform Contract Rule

- New event, method, route, key, DTO field, or config must be checked across Flutter, Android, iOS, Wear OS, watchOS, and backend when relevant.
- Avoid local-only assumptions that break shared fall timestamp, cancellation, or backend escalation behavior.
