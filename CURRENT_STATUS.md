# Fall Guardian — current status and handoff

> Functional status as of July 25, 2026.
>
> Read this file first when resuming work. Detailed architecture documentation
> stays in `docs/SYSTEM_OVERVIEW.md`, and the watch contract in
> `docs/COMPANION_ENROLLMENT.md`.

## 1. Starting point

- Reference branch: `main`.
- Last functional baseline before this handoff:
  `9397d29 feat(assisted): start secure watch enrollment (#81)`.
- PRs #73 to #81 merged after CI.
- Expected working tree: clean and in sync with `origin/main`.

Always confirm before starting:

```sh
git status --short --branch
git log -5 --oneline
make status
```

## 2. What works

### Backend

- stable identity for a protected person;
- multiple devices linked to the same person;
- deduplication by protected person + `clientAlertId`;
- versioned incident contract with `revision`, `detectionSource`, and
  `resolution`;
- server-side `cancelDeadlineAt` deadline;
- `watchos` or `wearos` enrollment valid for five minutes, single-use,
  platform-enforced, with the token stored only as an HMAC hash;
- caregiver notifications, receipts, acknowledgements, and history.

### Assisted person application

- phone registration and secure storage of its credentials;
- immediate incident registration, without waiting for the countdown to
  finish;
- cancellation, deferred location addition, and local history;
- receiving watchOS/Wear OS events;
- "Connect the watch" action in settings;
- enrollment creation and versioned transmission to the native bridge;
- waiting, error, expiration, and retry states;
- no enrollment token persisted or logged;
- Android requires exactly one connected watch before sending the secret.

### Watches

- watchOS: Apple system detection, accelerometer fallback when the app is
  open, countdown, cancellation, and WatchConnectivity relay;
- Wear OS: foreground detection service, countdown, cancellation, and Data
  Layer relay to Android;
- no watch consumes the enrollment yet;
- no watch sends an incident directly to the API yet.

### Caregiver application

- linking with multiple people;
- push reception, alert screen, and history;
- retry of history loading after an error;
- receipts and acknowledgements.

## 3. Next exact task — PR B watchOS

Goal: finish enrollment on the Apple Watch side, without yet adding direct
fall submission.

### Expected behavior

1. receive the `companionEnrollment` message sent by the iPhone;
2. verify `schemaVersion`, `platform`, token, and expiration;
3. immediately call
   `POST /api/v1/companion-enrollments/claim` with `URLSession`;
4. retrieve `deviceId` and `deviceToken`;
5. store `deviceToken` in Keychain and the non-sensitive metadata
   separately;
6. confirm only the `enrolled` status to the iPhone, never the secret;
7. keep the state after a restart;
8. offer a new enrollment if the secret is missing, corrupted, or rejected.

### Main files

- `apps/watchos/FallGuardian/FallGuardian Watch App/WatchSessionManager.swift`:
  WatchConnectivity reception and confirmation;
- new watchOS service dedicated to the `/claim` client;
- new Keychain storage dedicated to companion credentials;
- `apps/watchos/FallGuardianTests/`: contract, expiration, errors, and
  persistence;
- watchOS Xcode project and iOS project embedding the watch, if new Swift
  files must be referenced explicitly;
- `docs/COMPANION_ENROLLMENT.md` and `docs/SYSTEM_OVERVIEW.md`.

The incoming message is already produced by the phone:

```json
{
  "type": "companionEnrollment",
  "schemaVersion": 1,
  "platform": "watchos",
  "enrollmentToken": "<64 characters>",
  "expiresAt": "<ISO-8601 date>"
}
```

The API URL must come from an explicit build configuration. Never hardcode
a production URL or a secret. Do not accept an arbitrary URL from the
WatchConnectivity message.

### Completion criteria

- success, expiration, malformed response, and server rejection tested;
- duplicate delivery of the same message without duplicate identity;
- credentials available after the extension restarts;
- no token visible in the logs;
- iPhone confirmation contains no token;
- `make -C apps/watchos check` green;
- iOS app build with the embedded watch green;
- documentation updated.

## 4. Next steps after PR B

Recommended order:

1. PR C — Wear OS consumption + Android Keystore;
2. PR D — persistent queue and direct watchOS HTTPS;
3. PR E — direct Wear OS HTTPS + native Android relay independent of
   Flutter;
4. Safety UX: long-press "I'm OK", network states, and caregiver handling;
5. escalation, monitoring, privacy, and commercial readiness.

Do not merge PR B with direct fall submission. Keep each increment testable
and reversible.

## 5. Validations already performed

- backend: unit, integration, Behat, quality, and security tests;
- assisted app: 151 tests, static analysis, and coverage at or above 90%
  during PR #81;
- assisted Android APK built;
- iOS simulator app built with the embedded Watch companion;
- "Watch connection" screen inspected on simulator;
- existing deterministic watchOS/Wear OS builds and tests green in CI.

These validations do not prove full physical functioning.

## 6. Physical tests still required

No complete physical result is recorded to date. Test and record date, OS
versions, devices, network, and result for each case:

- real Apple Watch + locked iPhone in a pocket;
- watch without Wi-Fi, iPhone in range with 4G/5G;
- cellular Apple Watch without an iPhone;
- locked Android with the Flutter process killed;
- network loss and recovery during the delay;
- phone and watch restart;
- fall followed by near-simultaneous cancellation;
- simultaneous watch-direct and phone relay;
- multiple caregivers and multiple devices.

## 7. Blockers and external dependencies

### Apple

- team: Thomas Laure, Team ID `PTXCAH5P4R`;
- iOS app: `com.fallguardian.app`;
- Watch app: `com.fallguardian.app.watchkitapp`;
- Fall Detection capability request sent to Apple;
- known state: approved (entitlement assigned to the account, 2026-07-25);
- verified 2026-07-25: `xcodebuild -allowProvisioningUpdates` produces a
  signed watchOS build whose embedded entitlements confirm
  `com.apple.developer.health.fall-detection = true` under team
  `PTXCAH5P4R` — the capability is correctly configured and the
  provisioning profile is current;
- consequence: physical validation of `CMFallDetectionManager` on a real
  Apple Watch is no longer blocked by capability or signing state.

Do not add certificates or profiles to the repository.

### Access to hand over outside Git

Depending on their role, the person taking over will need:

- access to the Apple Developer account and Xcode signing;
- Firebase/FCM access;
- backend environment secrets and variables;
- access to the GitHub repository and Actions;
- test iPhone, Apple Watch, Android device, and Wear OS watch.

Secrets must be handed over through a secrets manager, never in this
file, an issue, or a PR.

## 8. Running locally

From the root:

```sh
make help
make status
make quality
```

Backend:

```sh
make -C backend/api up
make -C backend/api install
make -C backend/api test
make -C backend/api test-behat
```

Assisted person app:

```sh
make -C apps/assisted_mobile quality
make -C apps/assisted_mobile build-android
make -C apps/assisted_mobile build-ios
```

Watches:

```sh
make -C apps/watchos check
make -C apps/wear_os check
```

For physical devices and network changes, follow each project's README.
`BACKEND_BASE_URL` must be provided at build time; do not assume that
`localhost` refers to the Mac when running from a device.

## 9. Critical product limitations

- Fall Guardian does not automatically call emergency services;
- the current core function alerts linked caregivers via notification;
- old code and old Android labels related to SMS still exist and must be
  removed or clarified before commercialization;
- no transport can work without a network path on the watch or phone;
- the Android relay with a killed process is not yet guaranteed;
- revocation of a lost watch and token rotation are not implemented;
- escalation without caregiver handling is incomplete;
- retention, deletion, and false-positive policy to be defined;
- medical, emergency, privacy validation, and commercial promise still to
  be carried out before release.

## 10. Documentation map

- `CURRENT_STATUS.md`: operational status and next task;
- `docs/SYSTEM_OVERVIEW.md`: features, architecture, limitations, and
  roadmap;
- `docs/COMPANION_ENROLLMENT.md`: contract and PR A-to-E breakdown;
- `README.md`: monorepo structure and common commands;
- each project's README: project-specific install, build, and tests;
- root and local `CLAUDE.md` files: contribution rules.

Each topic has exactly one owning file: the merged-PR changelog and phased
roadmap live in `docs/SYSTEM_OVERVIEW.md` (§11, §14); the watch-enrollment
PR breakdown lives in `docs/COMPANION_ENROLLMENT.md` (§6). This file only
tracks the single next actionable task and current handoff state — update
the owning file first and link to it here rather than re-describing it.

Update this file after each major increment or change in blockers.
