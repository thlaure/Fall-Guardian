---
paths:
  - "backend/src/**/*.php"
  - "backend/config/**/*.yaml"
  - "backend/config/**/*.yml"
  - "flutter_app/lib/**/*.dart"
  - "caregiver_app/lib/**/*.dart"
  - "wear_os_app/**/*.kt"
  - "watchos_app/**/*.swift"
---

# Security Rules

- Never hardcode secrets, tokens, passwords, signing material, or private endpoints.
- Treat `.env`, `.env.*`, private keys, signing files, Firebase/APNs/FCM credentials, and local override files as sensitive.
- Enforce authorization server-side when access is scoped to a device, caregiver link, alert, or protected person.
- Treat phone, watch, caregiver app, backend, webhook, and push/SMS inputs as untrusted until validated.
- Validate and constrain incoming request data at the boundary before database writes or outbound calls.
- Prefer explicit allowlists over permissive pass-through behavior.
- Minimize API response data to fields intentionally exposed to clients.
- Do not expose internal exceptions, stack traces, SQL details, tokens, contact plaintext, or provider credentials in API responses.
- Be careful with raw SQL: parameterize values and keep query intent readable.
- Keep outbound requests bounded and safe when user-controlled data influences payloads or destinations.
- Add negative-path coverage for forbidden, invalid, unauthenticated, unlinked, duplicate, cancelled, or unsafe requests when relevant.
- Do not weaken static-analysis protections to make a warning disappear.
- Prefer fixing PHPStan findings in code, types, or PHPDoc rather than adding ignores or broadening `phpstan.neon`.

## Product-Specific Rules

- Phone-side sensitive data must stay behind secure storage, not plain shared preferences for primary persistence.
- Backend caregiver/contact delivery must preserve auditability of attempts and failures.
- Android local SMS is optional fallback/debug behavior only, not the primary production delivery contract.
- Backend-owned push notification delivery is the target production path for caregiver escalation.
- Cross-device cancel and fall-detected messages must preserve shared timestamp semantics and must not be echoed back in loops.

## AI Tool And MCP Policy

- MCP servers are blocked project-wide by default through `.claude/settings.json` (`allowedMcpServers: []`).
- Do not paste proprietary code, secrets, credentials, personal contact data, or safety-critical user data into external AI tools or web interfaces.
- Sensitive file classes are off-limits for AI context: `.env`, private keys, signing material, credentials, and any file matched by `.claudeignore`.
- When in doubt, ask before using AI assistance on authentication, notification delivery, contact data, medical/safety workflows, or billing/payment code.
