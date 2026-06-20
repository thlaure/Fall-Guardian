---
paths:
  - "src/**/*.php"
  - "config/**/*.yaml"
  - "config/**/*.yml"
---

# Security Rules

- Never hardcode secrets, tokens, passwords, FCM credentials, or private keys
- Treat `.env` and `.env.*` as sensitive — never read or commit them
- Validate and constrain incoming request data at the boundary (DTOs with Symfony Validator constraints)
- Prefer explicit allowlists over permissive pass-through behavior
- Do not expose internal exceptions, stack traces, or database details in API responses
- Be careful with raw SQL: parameterize values, keep intent readable
- Do not weaken static-analysis protections to make a warning disappear
- Prefer fixing PHPStan findings in code, types, or PHPDoc rather than broadening `phpstan.neon`

## Auth

- All device API endpoints must require a valid device token via `DeviceTokenAuthenticator`
- Do not expose device token hashing logic or token values in responses, logs, or test fixtures
- Authorization checks must happen before any state mutation or side effect
- Anonymous access to protected endpoints must be impossible; verify firewall config when adding routes

## Push / External Integrations

- FCM credentials (`FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON`) must come from environment configuration only
- Do not log full push payloads if they contain device identifiers or user data
- `FakePushGateway` is for development/test only — never allow it in production without explicit `PUSH_PROVIDER=fake`
- Outbound HTTP calls must be bounded and timeout-aware

## Data Handling

- Device tokens and push tokens are sensitive identifiers — treat as credentials
- Do not expose raw database IDs where UUIDs are used
- Do not log alert payloads or caregiver contact details in production
- Messenger message payloads must not contain secrets or unmasked sensitive data

## Input Validation

- All write endpoints must use Symfony Validator constraints on Input DTOs
- Enums must be validated via PHP backed enums or explicit constraint
- UUIDs must be validated with `#[Assert\Uuid]`
- Do not trust client-provided device identifiers without token verification
