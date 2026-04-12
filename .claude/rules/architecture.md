# Architecture Rules

- Read `AGENTS.md` first. It is the canonical source of repository-specific rules.
- Apply SOLID principles pragmatically.
- Prefer clean architecture and ports/adapters when the local code already uses them.
- Keep Flutter screens thin; workflow belongs in coordinators/services, persistence in repositories.
- Keep native bridges thin. Android/iOS/watch code should translate platform/runtime events, not own product workflow.
- Keep backend controllers/processors thin. Application services and Messenger handlers own delivery workflow.
- Validate external input at DTO or boundary level before side effects.
- Keep repositories focused on persistence. Do not hide business decisions in persistence adapters.
- Mirror the local project shape instead of forcing one architecture style across Flutter, native, and backend.
- Prefer incremental changes that reuse existing conventions over broad restructuring.
- Optimize first for readability and reviewability.
- If there is no measured performance issue, prefer the simpler and more readable solution.
- The final code should be easy for a human reviewer to understand quickly.
