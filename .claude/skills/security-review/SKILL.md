---
name: security-review
description: Use when the user asks for a security review or mentions auth, device tokens, push credentials, Firebase, invite codes, local storage, networking, or unsafe external interactions.
---

# Security Review

Read first:

- `AGENTS.md`
- project-local `AGENTS.md` for touched projects
- `.claude/rules/security.md`
- `.claude/rules/testing.md`

Workflow:

1. Scope the change and touched trust boundaries.
2. Trace sensitive inputs and outputs.
3. Check auth, authorization, rate limits, token handling, storage, logging, and
   network behavior.
4. Verify negative tests exist where abuse or failure is plausible.
5. Report only concrete findings tied to code paths.
