# Fall Guardian Backend API

Symfony/API Platform backend for device identity, caregiver linking, fall-alert
persistence, alert history, push notification delivery, and acknowledgement.

## Responsibilities

- Register assisted-person and caregiver devices.
- Authenticate device API calls with bearer device tokens.
- Hash device tokens with an HMAC-based secret.
- Create short-lived caregiver invite codes.
- Link caregivers to assisted-person devices.
- Persist active, acknowledged, and cancelled fall alerts.
- Store caregiver push tokens.
- Dispatch backend-owned push notifications.
- Persist push delivery attempts for auditability.
- Rate-limit public and safety-critical endpoints.
- Expose OpenAPI documentation for the mobile clients.

## Runtime Flow

```text
watch detects fall
-> assisted phone owns countdown through AlertCoordinator
-> timeout submits POST /api/v1/fall-alerts
-> backend persists FallAlert
-> backend dispatches SendFallAlertPushMessage
-> messenger handler sends push to linked caregiver devices
-> caregiver app fetches alert detail/history
-> caregiver can acknowledge the alert
```

If the assisted user cancels the countdown, the assisted app calls
`POST /api/v1/fall-alerts/{clientAlertId}/cancel`. The backend stores the
cancelled alert so it remains visible in caregiver history.

## Architecture

Business code is organized by domain under `src/Domain`. Framework and external
adapters live under `src/Infrastructure`.

```text
src/
├── Domain/
│   ├── Alert/
│   │   ├── Handler/
│   │   ├── Message/
│   │   ├── Port/
│   │   ├── Processor/
│   │   ├── Provider/
│   │   ├── Request/
│   │   ├── Response/
│   │   └── Service/
│   ├── Caregiver/
│   ├── Debug/
│   ├── Device/
│   ├── Healthcheck/
│   └── Push/
├── Entity/
├── Enum/
└── Infrastructure/
```

Typical write flow:

```text
Request DTO
-> API Platform Processor
-> Domain Service or Handler
-> Repository / Gateway Port
-> Infrastructure adapter
-> Entity / database / external provider
-> Response DTO
```

Typical read flow:

```text
API Platform Provider
-> Repository Port
-> Doctrine adapter
-> Response DTO
```

## Public API

- `POST /api/v1/devices/register`: register an assisted or caregiver device.
- `POST /api/v1/fall-alerts`: create an escalated fall alert.
- `GET /api/v1/fall-alerts/{id}`: retrieve one fall alert.
- `POST /api/v1/fall-alerts/{clientAlertId}/cancel`: persist a cancelled fall.
- `POST /api/v1/invites`: create a caregiver invite code.
- `POST /api/v1/invites/{code}/accept`: link a caregiver using an invite.
- `POST /api/v1/caregiver/push-token`: store a caregiver push token.
- `GET /api/v1/caregiver/alerts`: list caregiver-visible alerts.
- `POST /api/v1/fall-alerts/{id}/acknowledge`: acknowledge an alert.
- `GET /health`: health check endpoint.

Development/debug endpoint:

- `GET /debug/fake-push`: inspect fake push messages outside production when
  the fake push provider is configured.

API documentation:

```text
http://localhost:8002/docs
http://localhost:8002/docs.jsonopenapi
```

## Local Setup

Start containers:

```sh
make up
```

Install dependencies and run migrations:

```sh
make install
```

The Makefile uses `podman compose` when Podman is installed, otherwise
`docker compose`.

## Configuration

Core environment variables:

- `APP_SECRET`: Symfony application secret.
- `DEVICE_TOKEN_HASH_SECRET`: HMAC secret for device token hashing.
- `DATABASE_URL`: PostgreSQL connection string.
- `MESSENGER_TRANSPORT_DSN`: primary async messenger transport.
- `MESSENGER_FAILED_TRANSPORT_DSN`: failed-message transport.
- `TRUSTED_PROXIES`: proxies trusted for client IP resolution.
- `APP_SHARE_DIR`: shared runtime directory.
- `PUSH_PROVIDER`: `fake` or `fcm`.
- `FCM_PROJECT_ID`: Firebase project ID when FCM is enabled.
- `FCM_SERVICE_ACCOUNT_JSON`: Firebase service-account JSON when FCM is enabled.

Do not commit production values. Use local `.env.local`, CI secrets, or runtime
secret injection.

## Push Providers

`fake` writes outgoing messages under:

```text
var/share/fake_push_inbox.jsonl
```

Use it for local end-to-end testing without Firebase. Use `fcm` only when the
Firebase service account is configured securely.

## Quality Checks

Run all backend deterministic checks:

```sh
make quality
```

Individual checks:

```sh
make lint-dry
make analyse
make rector-dry
make security-check
```

## Tests

Prepare the test database:

```sh
make test-db
```

Run PHPUnit:

```sh
make test-unit
make test-integration
make test
```

Run Behat API scenarios:

```sh
make test-behat
```

Generate HTML coverage:

```sh
make coverage-html
```

## Operations

Useful commands:

```sh
make logs
make logs-app
make logs-messenger
make ps
make routes
make migrate
make messenger-consume
make worker-failed
make worker-retry
```

Run any Symfony command:

```sh
make console CMD="debug:router"
```

## Security Notes

- Device authentication depends on bearer tokens; never log plaintext tokens.
- Device token hashes are HMAC-based and require `DEVICE_TOKEN_HASH_SECRET`.
- Public endpoints are rate-limited; preserve this when adding new endpoints.
- FCM error messages must not expose raw provider response bodies to clients.
- Keep trusted proxy configuration correct in production, otherwise IP-based
  rate limiting can group all users behind one proxy IP.

## Related Projects

- `../../apps/assisted_mobile`: assisted person phone app.
- `../../apps/caregiver_mobile`: caregiver phone app.
- `../../apps/wear_os`: Wear OS watch app.
- `../../apps/watchos`: Apple Watch app.
