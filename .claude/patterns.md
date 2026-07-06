# Fall Guardian Patterns

Check the owning project's `CLAUDE.md` (see root `CLAUDE.md` → Layout for
the full project list) before creating new patterns — match its existing
conventions first.

Shared principles:

- Put behavior in the owning project.
- Keep cross-project contracts explicit and tested.
- Keep safety-critical alert flows readable.
- Prefer deterministic quality tools before agent judgment.
- Add a local pattern only after the same shape appears more than once and
  reduces real complexity.

These are patterns, not rigid templates — match the surrounding code in the
target area before introducing a new shape.

## Backend: new domain endpoint (Request → Processor → Service → Response)

Add all four pieces together; never a Processor without its DTO+test.

**Request DTO** (`src/Domain/{Domain}/Request/{Verb}{Noun}InputDTO.php`) —
declares the API Platform operation:

```php
#[ApiResource(operations: [
    new Post(
        uriTemplate: '/api/v1/fall-alerts/{clientAlertId}/location',
        output: FallAlertOutputDTO::class,
        read: false,
        openapi: new Operation(
            tags: ['Fall alerts'],
            summary: 'Attach a location fix to an already-reported fall alert',
            security: [['deviceBearer' => []]],
        ),
        processor: AttachFallAlertLocationProcessor::class,
    ),
])]
final class AttachFallAlertLocationInputDTO
{
    #[Assert\Range(min: -90, max: 90)]
    public ?float $latitude = null;

    #[Assert\Range(min: -180, max: 180)]
    public ?float $longitude = null;
}
```

**Processor** (`src/Domain/{Domain}/Processor/{Verb}{Noun}Processor.php`) —
owns auth, device-role guard, and calling the domain service. No business
logic here beyond wiring:

```php
final readonly class AttachFallAlertLocationProcessor implements ProcessorInterface
{
    public function __construct(
        private AlertIngestionServiceInterface $alertIngestionService,
        private DeviceContextInterface $currentDeviceProvider,
    ) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): FallAlertOutputDTO
    {
        if (!$data instanceof AttachFallAlertLocationInputDTO) {
            throw new BadRequestHttpException('Invalid fall alert location payload.');
        }

        $clientAlertId = $uriVariables['clientAlertId'] ?? null;
        if (!is_string($clientAlertId) || '' === $clientAlertId) {
            throw new NotFoundHttpException('Alert not found.');
        }

        $device = $this->currentDeviceProvider->requireDevice();
        if ($device->isCaregiver()) {
            throw new AccessDeniedHttpException('Caregiver devices cannot update protected-person fall alerts.');
        }

        $alert = $this->alertIngestionService->attachLocation($device, $clientAlertId, $data->latitude, $data->longitude);
        if (!$alert instanceof FallAlert) {
            throw new NotFoundHttpException('Alert not found.');
        }

        return FallAlertOutputDTO::fromEntity($alert);
    }
}
```

**Service method** — the actual business rule, on the existing domain
service interface + implementation:

```php
public function attachLocation(Device $device, string $clientAlertId, ?float $latitude, ?float $longitude): ?FallAlert
{
    $alert = $this->fallAlertRepository->findOneByDeviceAndClientAlertId($device, $clientAlertId);
    if (!$alert instanceof FallAlert) {
        return null;
    }

    $alert->updateLocation($latitude, $longitude);
    $this->fallAlertRepository->save($alert);

    return $alert;
}
```

**Test** (`tests/Unit/Domain/{Verb}{Noun}ProcessorTest.php`) — mock the
service interface + `DeviceContextInterface`, cover: success, not-found,
caregiver-device-rejected, wrong-payload-type:

```php
final class AttachFallAlertLocationProcessorTest extends TestCase
{
    private AlertIngestionServiceInterface&MockObject $alertIngestionService;
    private DeviceContextInterface&MockObject $currentDeviceProvider;
    private AttachFallAlertLocationProcessor $processor;

    protected function setUp(): void
    {
        $this->alertIngestionService = $this->createMock(AlertIngestionServiceInterface::class);
        $this->currentDeviceProvider = $this->createMock(DeviceContextInterface::class);
        $this->processor = new AttachFallAlertLocationProcessor($this->alertIngestionService, $this->currentDeviceProvider);
    }

    #[Test]
    public function itRejectsCaregiverDevices(): void
    {
        $device = $this->createMock(Device::class);
        $device->method('isCaregiver')->willReturn(true);
        $this->currentDeviceProvider->method('requireDevice')->willReturn($device);
        $this->alertIngestionService->expects($this->never())->method('attachLocation');

        $this->expectException(AccessDeniedHttpException::class);
        $this->processor->process($this->buildDto(), $this->createMock(Operation::class), ['clientAlertId' => 'client-001']);
    }
}
```

Rate-limit endpoints that mutate state or are reachable pre-auth
(`$this->rateLimiter->consume('bucket_name', $limit, $windowSeconds, $device->getPublicId())`),
matching `.claude/rules/security.md`'s "public and safety-critical
endpoints must stay rate-limited."

## Flutter: backend gateway port + implementation + consumer

Adding a new backend call from a Flutter app always touches three files —
never add a method to `BackendApiService` without adding it to the port
interface first.

**Port** (`lib/services/alert_ports.dart` or the app's equivalent ports
file) — the abstraction the domain-ish service code depends on, so tests
can fake it:

```dart
abstract class AlertBackendGateway {
  Future<void> attachLocation({
    required String clientAlertId,
    required double latitude,
    required double longitude,
  });
}
```

**Implementation** (`lib/services/backend_api_service.dart`) — owns the
actual HTTP call, credential refresh, and error mapping to
`BackendApiException`:

```dart
@override
Future<void> attachLocation({
  required String clientAlertId,
  required double latitude,
  required double longitude,
}) async {
  final token = await _store.read(_deviceTokenKey);
  if (token == null || token.isEmpty) return;

  final response = await _send(
    _client.post(
      Uri.parse('$_baseUrl/api/v1/fall-alerts/$clientAlertId/location'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    ),
    'Fall alert location attachment timed out',
  );

  if (response.statusCode == 404) return;
  if (!_isSuccess(response.statusCode)) {
    throw BackendApiException('Failed to attach fall alert location',
        statusCode: response.statusCode, body: response.body);
  }
}
```

**Consumer** (e.g. `lib/services/alert_coordinator.dart`) — calls through
the port, never the concrete class, and treats non-critical calls as
best-effort:

```dart
Future<void> _attachLocationWhenAvailable(int timestamp, String clientAlertId) async {
  final position = await _locationProvider.getCurrentPosition();
  if (position == null || !_isCurrentAlert(timestamp)) return;

  try {
    await _backendGateway.attachLocation(
      clientAlertId: clientAlertId,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (_) {
    // Best-effort enhancement data only — the alert is already registered
    // regardless of whether this call succeeds.
  }
}
```

**Test fake** — extend the shared `_FakeBackendGateway` in the relevant
`test/services/*_test.dart` with the new method (never a partial fake that
throws `UnimplementedError` for methods the port declares).

## Watch apps: threshold setting must reach the real trigger

Any user-facing sensitivity setting (`thresh_*`) must be read by
`FallAlgorithm`/`FallAlgorithm.kt` and actually change the boolean trigger
expression — not just be tracked/logged. Prove it with a test pair: one
case where raising the threshold suppresses a trigger that fired below it,
using the same input otherwise. See `FallAlgorithmTest.kt` /
`FallAlgorithmTests.swift` for the tilt-threshold example.
