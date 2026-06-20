---
paths:
  - "backend/api/src/**/*.php"
  - "apps/assisted_mobile/lib/**/*.dart"
  - "apps/caregiver_mobile/lib/**/*.dart"
  - "apps/wear_os/**/*.kt"
  - "apps/watchos/**/*.swift"
---

# Architecture Rules

- Keep the monorepo modular. Do not turn it into one shared application layer.
- Put behavior in the project that owns it.
- Preserve cross-project contracts when changing alerts, devices, invites, push
  tokens, acknowledgement, cancellation, or history.
- Prefer one PR for cross-project contract changes so API and app changes stay
  testable together.
- Keep framework, platform, storage, and network concerns at the edges.
- Prefer explicit, readable code over clever abstractions.
- Apply SOLID as a review heuristic, not as a reason to multiply classes.
- Add abstractions only when they remove real complexity or protect a real
  boundary.
- Keep user-facing safety flows boring, clear, and highly testable.

## Backend

- Follow `backend/api/AGENTS.md` for domain, API Platform, CQRS-like handler,
  port, and infrastructure patterns.
- Preserve the `/api/v1` API prefix.
- Keep business flow in handlers/services, not controllers or processors.

## Flutter Apps

- Follow the local `AGENTS.md`.
- Keep widgets focused on presentation and simple interaction glue.
- Keep backend, notification, storage, and platform logic in services.
- Prefer readable Dart and concise comments for platform behavior, async flows,
  permissions, background execution, and safety-critical alert behavior.

## Watch Apps

- Keep detection logic explicit and testable.
- Any UI threshold setting must affect the real detection rule.
- Watches report possible falls to the assisted phone; they do not notify
  caregivers directly.
