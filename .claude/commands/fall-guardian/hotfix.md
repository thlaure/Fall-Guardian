Prepare and implement an urgent Fall Guardian hotfix with the smallest safe change set.

Production issue or urgent scope: `$ARGUMENTS`

Workflow:
1. Confirm the issue is truly urgent and production-facing.
2. Reproduce or localize the failure quickly from logs, crash reports, or the current diff.
3. Identify the narrowest safe fix with the smallest blast radius.
4. Prefer a dedicated `hotfix/...` branch if the current branch is shared or protected.
5. Implement the minimal change only. No opportunistic refactor.
6. Add the smallest regression coverage the repo can express.
7. Run the narrowest relevant verification:
   - Flutter change: `make check`
   - Backend change: PHPStan + PHPUnit unit suite via Docker
   - Both: run both
8. Prepare a Conventional Commit message and deployment notes.
9. Ask for confirmation before any `git commit` or `git push`.

Rules:
- Speed matters, but correctness still beats panic.
- Cross-platform contract changes (MethodChannel keys, FCM payload, API fields) must stay aligned across all affected layers even during a hotfix.
- If the real fix is large, prefer a safe containment change plus a follow-up task.
- Keep the diff extremely narrow and easy to review.
- Surface any skipped verification explicitly.
