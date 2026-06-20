---
name: karpathy-guidelines
description: Use this skill as an execution discipline modifier for review, refactor, ambiguous implementation, or quality-sensitive tasks. Trigger on requests that mention Karpathy principles, anti-slop, careful implementation, minimal diff, or strong reviewability.
---

# Karpathy Guidelines

Apply these principles while using the repository-specific rules in `AGENTS.md`.

## Think Before Coding

- State material assumptions explicitly.
- Surface ambiguity that can lead to the wrong implementation.
- Ask when the missing information is risky enough to change the solution.

## Simplicity First

- Prefer the minimum implementation that fully satisfies the request.
- Avoid speculative abstractions, generic frameworks, and configurability not required by the task.
- Prefer clear naming and direct control flow over cleverness.

## Surgical Changes

- Touch only what is needed for the request and verification.
- Do not refactor adjacent code unless correctness or the requested change requires it.
- Clean up only dead code, imports, variables, or formatting made obsolete by your change.

## Verifiable Outcome

- Define success in terms that can be tested or inspected.
- Bug fix: reproduce first when practical, then verify the fix.
- Behavior change: add or update tests that demonstrate the intended behavior.
- Refactor: verify behavior before and after with the relevant suite.

## Human Reviewability

- Optimize for code a human reviewer can understand quickly.
- If performance and readability conflict and no bottleneck is measured, choose readability.
- Explain non-obvious tradeoffs in the final response.
