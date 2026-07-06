---
name: review-pr-feedback
description: Use when the user asks to address PR review comments, check CI status on a PR, or reports "the PR failed" / "check the review comments" / "why did CI fail". Covers GitHub pull requests via the gh CLI.
---

# Review PR Feedback

## Workflow

1. Identify the PR: `gh pr view <number>` (or the current branch's PR if
   none given).
2. Pull review comments and CI status:
   - `gh pr view <number> --comments` for review/discussion comments
   - `gh api repos/{owner}/{repo}/pulls/<number>/comments` for inline
     code-review comments tied to specific diff lines
   - `gh pr checks <number>` for CI status; `gh run view <run-id> --log-failed`
     to pull failure logs for a specific failing job
3. Triage each comment/failure: is it a real defect, a style nit already
   covered by a deterministic tool, or a misunderstanding worth replying to
   instead of changing code?
4. Fix real issues on the PR's existing branch — do not open a new branch
   for review-feedback fixes.
5. Run the relevant project's quality command (see `verify-quality`) before
   pushing.
6. Push the fix commit; do not force-push over review history unless the
   user explicitly asks for it.

## Rules

- Never silently ignore a reviewer comment — either fix it or explain in
  the response why it's not being changed.
- CI failures: fix the root cause. Re-running a flaky/transient failure
  (`gh run rerun <id> --failed`) is fine only after confirming the failure
  is unrelated to the PR's own diff.
- Confirm before `git push` unless the user already explicitly asked to
  push in this conversation.
