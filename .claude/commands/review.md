Review all files changed since the last commit. Run `git diff HEAD` and `git diff --cached` to get the full diff, then `git diff HEAD --name-only` to list changed files.

For every changed file, apply the checklist below and report findings grouped into three tiers:

**🔴 Critical** — bugs, security issues, data loss risk. Must fix before commit.
**🟡 Warning** — bad practices, maintainability issues, missing guards. Should fix.
**🔵 Suggestion** — architecture improvements, enhancements, clarity. Nice to have.

If a tier has no findings, omit it. If a file has no findings at all, skip it. End with a one-line verdict: ✅ Ready to commit / ⚠️ Fix warnings first / 🚫 Fix critical issues first.

---

## Checklist

### Flutter / Dart

**Safety**
- Every `await` inside a `State` method is followed by `if (!mounted) return` before any `setState` or `Navigator` call
- `dispose()` cancels all `Timer`, `StreamSubscription`, and `AnimationController` instances
- No `BuildContext` stored across async gaps without a `mounted` guard
- `unawaited()` is explicit for intentional fire-and-forget futures (not silent `// ignore`)

**Architecture**
- Screens only call services and repositories — no cross-screen calls, no business logic in widgets
- Services are stateless; mutable state lives in repositories or state objects
- Repositories handle all persistence; no `SharedPreferences` calls outside repository classes
- Models are pure Dart — no Flutter imports, no platform dependencies

**Quality**
- No dead code, unused imports, or commented-out blocks
- Public methods have clear names; no single-letter variables outside loop counters
- Error paths are handled (no silent `catch (_) {}` unless explicitly intentional with a comment)
- No hardcoded strings that should be in `l10n` (user-visible text, error messages)

---

### Security

- No hardcoded credentials, API keys, or secrets anywhere in the diff
- User input is validated at the boundary: name length capped, phone format checked, no raw HTML/JS injection surface
- `SharedPreferences` is used only for non-sensitive data (thresholds, timestamps, contacts metadata) — never for tokens or passwords
- Incoming watch messages are validated: source node verified, event type checked against known values, payload parsed defensively
- Intents verified as trusted before acting on extras (see `isTrustedIntent` pattern in Android `MainActivity`)

---

### Native — Kotlin (Android / Wear OS)

- No strong capture of `Activity` or `Context` in long-lived objects; use `WeakReference` or `applicationContext`
- `[weak self]` equivalent: lambda captures that outlive the calling scope use weak references
- UI updates (`setState`, `runOnUiThread`, Compose state writes) happen on the main thread
- All registered listeners (`SensorManager`, `SharedPreferences.OnSharedPreferenceChangeListener`, `BroadcastReceiver`) are unregistered in the corresponding lifecycle teardown
- `WakeLock` is always released in `onDestroy`; no unbounded acquisition

---

### Native — Swift (iOS / watchOS)

- `[weak self]` in every closure that captures `self` and outlives the call site (especially `DispatchQueue.async`, `addObserver`, completion handlers)
- `WCSession` calls guarded by `activationState == .activated` and `isReachable` where appropriate
- `NotificationCenter` observers removed in `deinit` or `stop()`
- `UserDefaults.synchronize()` called after batch writes that must be available immediately to other processes (watch ↔ phone)
- No force-unwrap (`!`) on optionals that can realistically be nil at runtime

---

### Cross-platform consistency

- New `MethodChannel` method added on Flutter side? → handler implemented on **both** Android (`MainActivity.kt`) and iOS (`AppDelegate.swift` / `WatchSessionManager.swift`)
- New `SharedPreferences` / `UserDefaults` key? → exact same string used across Flutter, Wear OS, and watchOS
- New watch event type? → handled in `WearDataListenerService` (Android) **and** `WatchSessionManager` (iOS)
- New threshold or config value? → default matches across all four apps
- Permission added on one platform? → check if equivalent is needed on others

---

### Architecture (project-level)

- Does the change respect the layering: `screens → services/repositories → models`?
- Is new logic placed in the right layer (no SMS logic in a screen, no UI state in a repository)?
- Could the change cause a regression in the watch→phone or phone→watch message flow?
- Does any new in-memory state need to survive app restarts? If so, is it persisted?
- Is the change covered by at least one test? If not, is there a clear reason why it can't be?
