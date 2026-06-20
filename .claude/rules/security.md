---
paths:
  - "**/*"
---

# Security Rules

- Never hardcode secrets, tokens, passwords, API keys, FCM credentials, private
  keys, certificates, signing material, or service-account JSON.
- Do not commit generated native Firebase files:
  - `apps/caregiver_mobile/android/app/google-services.json`
  - `apps/caregiver_mobile/ios/Runner/GoogleService-Info.plist`
- Treat `.env`, `.env.*`, local signing files, and machine-specific config as
  sensitive.
- Do not log device tokens, push tokens, invite codes, exact user locations, or
  full push payloads.
- Treat all mobile and push payloads as untrusted input.
- Bound outbound HTTP calls with timeouts.
- Do not expose raw provider errors, stack traces, SQL errors, or internal
  exception details to clients.
- Prefer allowlists over permissive pass-through behavior.
- Do not weaken static-analysis or security-tool configuration to make a warning
  disappear.

## Backend

- All protected API endpoints must require a valid device token.
- Authorization checks must happen before state mutation or side effects.
- Public and safety-critical endpoints must stay rate-limited.
- Device token hashing requires `DEVICE_TOKEN_HASH_SECRET`.
- FCM credentials must come from runtime configuration only.

## Mobile And Watches

- Store sensitive local data in secure storage when available.
- Avoid plaintext persistence for alert data that includes personal details.
- Do not bypass platform permission flows.
- Keep debug automation disabled or unexported in production builds.
