---
paths:
  - "backend/src/**/*.php"
  - "flutter_app/lib/**/*.dart"
  - "caregiver_app/lib/**/*.dart"
  - "wear_os_app/**/*.kt"
  - "watchos_app/**/*.swift"
---

# Architecture Rules

- Read `AGENTS.md` first. It is the canonical source of repository-specific rules.
- Apply SOLID principles pragmatically; use them to clarify ownership, not to multiply abstractions.
- Prefer explicit, readable designs over indirection-heavy abstractions.
- Keep safety-critical alert flow easy to review.

## Backend

- New backend business features belong in `backend/src/Domain/<Feature>/...`.
- Follow the nearest existing domain pattern; do not reintroduce top-level `Application/`, `UI/`, or `Message/` backend layers.
- Keep API Platform resources, state processors/providers, handlers, messages, ports, and controllers close to their domain.
- Use API Platform directly when it cleanly solves CRUD, serialization, validation, or read-only behavior.
- Use custom processors/providers/handlers when business workflow, authorization, idempotency, delivery, or cross-entity orchestration is involved.
- Keep controllers and API Platform processors/providers focused on request/API orchestration.
- Keep handlers and focused services as the main place for application/business flow.
- Keep repositories focused on persistence and data access; avoid moving business branching into persistence adapters.
- Keep DTOs, request objects, response/view objects, and API resource classes logic-free.
- Keep Doctrine entities focused on ORM mapping and simple state transitions.
- Keep external integrations at the edge in `Infrastructure/`, behind domain ports when variation, replacement, or testing needs are real.
- Preserve backend API prefix `/api/v1`.
- Domain routes are discovered from `backend/src/Domain/`.
- Backend alert escalation and caregiver notification delivery stay handler/service-driven, not controller-driven.
- Typical backend write flow: `ApiResource DTO -> State Processor -> Handler/Service -> Port/Repository/Gateway -> View/Output DTO`.
- Typical backend read flow: `ApiResource View -> State Provider -> Repository/Service -> View DTO`.
- Typical controller flow: `Controller -> request params/body -> Handler/Repository/Gateway -> Response`.
- Typical Messenger flow: `Message -> MessageHandler -> Repository/Service/Gateway -> persisted audit`.

## Flutter Phone Apps

- `AlertCoordinator` owns protected-person alert lifecycle, timeout, cancel propagation, and escalation.
- Flutter widgets render state and trigger intents; they do not own workflow timers or delivery side effects.
- Persistence belongs in repositories; plugin/platform/runtime integrations stay behind services or ports.
- Caregiver app screens should stay UI-only as backend-owned caregiver workflows are added.

## Native Bridges

- Native Android/iOS/watch code receives platform events and translates them into shared app events.
- Keep native bridges thin. Android/iOS/watch code should not duplicate product workflow decisions.
- Treat cross-device messages as untrusted until validated.

## Cross-Platform Contracts

- Check new event names, method names, payload keys, route contracts, and state meanings across Flutter, Android, iOS, Wear OS, watchOS, and backend when relevant.
- Do not add local-only assumptions that break shared fall timestamp, cancellation behavior, or backend escalation semantics.
