Implement a new Fall Guardian feature by mirroring the local repository patterns.

User request: `$ARGUMENTS`

Execution order:
1. Run the equivalent of `/fall-guardian:scan-project` if context is incomplete.
2. Find one nearby example in the same area and mirror its structure.
3. Implement the smallest coherent slice that satisfies the request.
4. Write tests in the same session.
5. Run the repository quality gates before reporting completion.

Default expectations unless the repo clearly differs:
- Follow SOLID principles.
- Prefer clean architecture and hexagonal boundaries when the project already uses them.
- If a framework-native solution already provides a direct, readable implementation in the local layer, use it instead of adding extra layers.
- Framework entrypoints stay thin.
- Input validation happens at the DTO or request boundary.
- Business logic lives in the owning layer for the platform or flow: coordinator, handler, use-case, or domain service.
- Repositories handle persistence only.
- Output shaping is explicit through DTOs, resources, or entity serialization.
- Prefer simple, readable code over clever or highly optimized code.
- If performance and readability conflict and there is no measured bottleneck, choose readability.
- Keep the result easy for a human reviewer to follow.

Checklist:
1. Confirm the target flow and owning layer: Flutter coordinator, native bridge, backend application service, API Platform native read side, or a cross-platform contract.
2. Reuse existing naming and file placement conventions.
3. Keep `declare(strict_types=1);` and modern PHP syntax.
4. Add or update validation at the input boundary.
5. Keep exceptions and HTTP error mapping aligned with the existing project.
6. Add the right tests:
   - unit tests for behavior and orchestration
   - integration tests when persistence behavior changes
   - API tests when endpoint behavior changes
7. Verify with the commands exposed by the repo `Makefile` files and `AGENTS.md`.

Avoid:
- business logic in widgets, controllers, or framework entrypoints
- new dependencies without explicit approval
- schema changes without explicit approval
- adding indirection when the local framework or layer can solve the case directly and cleanly
- premature optimization or indirection that hurts readability
- project reshaping when the request only needs a local change
