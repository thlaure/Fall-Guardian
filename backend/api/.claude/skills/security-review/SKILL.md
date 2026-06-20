---
name: security-review
description: Use this skill when the user asks for a security review or mentions auth/authz, device tokens, push credentials, validation, SQL safety, or unsafe external interactions in fall_guardian_api. Also trigger on phrases like "is this secure", "check the security of", "could this be exploited", or "are there vulnerabilities here".
---

# Security Review

Read first:
- `AGENTS.md`
- `.claude/rules/security.md`
- `.claude/rules/architecture.md`
- `.claude/rules/testing.md`

Read as needed:
- the relevant diff and nearby files

Workflow:
1. Inspect authentication and authorization boundaries (DeviceTokenAuthenticator, firewall config).
2. Check request validation and DTO boundaries.
3. Check push credential handling and FCM integration.
4. Check secrets, Messenger payload safety, and outbound interactions.
5. Check output exposure and error leakage.
6. Check negative-path tests for invalid or forbidden behavior.

Rules:
- Tie findings to concrete code paths.
- Prefer actionable findings over generic warnings.
