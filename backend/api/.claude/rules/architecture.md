---
paths:
  - "src/**/*.php"
---

# Architecture Rules

- New business features belong in `src/Domain/<Feature>/...`
- Follow the nearest existing local pattern inside the target domain
- Prefer Clean Architecture directionally for new and changed code: business flow in handlers/services, transport at the processor/controller boundary, persistence behind port interfaces
- State Processors and Controllers own routing and orchestration only
- Handlers own business orchestration
- Port interfaces (`src/Domain/<Feature>/Port/`) define the boundary between domain and infrastructure
- Doctrine implementations live in `src/Infrastructure/Persistence/` — never inside the domain folder
- DTOs and Response objects stay logic-free
- Entities stay focused on ORM mapping and simple state transitions
- Keep API Platform, HTTP concerns, Doctrine-specific details, and push integrations at the edges

Typical flows:

- API Platform write: `ApiResource DTO -> State Processor -> Handler/Service -> Port -> Infrastructure`
- API Platform read: `ApiResource View -> State Provider -> Port -> Infrastructure -> View DTO`
- Messenger: `Message -> MessageHandler -> Port/Service -> persisted state`

Rules:

- Keep API Platform CRUD under `/api/` framework-native unless custom business logic requires a domain handler
- Keep domain boundaries explicit and avoid cross-domain internals coupling
- Preserve API prefix `/api/v1`
- Routes are discovered from `src/Domain/`
- Do not introduce top-level `src/DTO/`, `src/Handler/`, or `src/Repository/` layers
- Apply SOLID as a decision aid, not a reason to multiply abstractions
- Prefer composition over inheritance for new behavior unless the local module already uses inheritance intentionally
- Prefer explicit, readable designs over indirection-heavy abstractions
- Avoid speculative generalization
