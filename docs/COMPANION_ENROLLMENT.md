# Watch enrollment — contract and integration plan

> Reference status as of July 25, 2026.
>
> Server support has been available on `main` since PR
> [#79](https://github.com/thlaure/Fall-Guardian/pull/79). The phone
> application can create and transmit the enrollment. The watchOS and Wear
> OS apps do not consume it yet.
>
> This file owns the enrollment contract and its client PR breakdown (§6).
> The overall system roadmap phases live in `docs/SYSTEM_OVERVIEW.md` (§14);
> the current handoff state and next actionable task live in
> `CURRENT_STATUS.md`.

## 1. Goal

Each watch must become its own authenticated device, linked to the same
protected person as the phone. The watch never receives the phone's
durable token.

The flow must work without manual entry of a long secret:

1. the authenticated phone requests an enrollment for its platform;
2. the API returns an ephemeral token valid for five minutes;
3. the phone transmits this token to the associated watch;
4. the watch exchanges the token for its own credentials;
5. it stores these credentials securely;
6. it can then send incidents and cancellations directly to the API.

## 2. Available API contract

### 2.1 Create an enrollment from the phone

```http
POST /api/v1/companion-enrollments
Authorization: Bearer <phone's deviceToken>
Content-Type: application/json

{
  "platform": "watchos"
}
```

`platform` only accepts `watchos` or `wearos`.

Response `201`:

```json
{
  "enrollmentToken": "<64-character token>",
  "expiresAt": "2026-07-25T10:05:00+00:00"
}
```

Only a device linked to a protected person can create this enrollment. A
caregiver device receives a `422` error. Creation is rate-limited per
protected device.

### 2.2 Consume the enrollment from the watch

This call is public because the watch does not yet have credentials.

```http
POST /api/v1/companion-enrollments/claim
Content-Type: application/json

{
  "enrollmentToken": "<token received from the phone>",
  "platform": "watchos",
  "appVersion": "1.0.0"
}
```

Response `201`:

```json
{
  "deviceId": "<watch-specific identifier>",
  "deviceToken": "<watch-specific secret>"
}
```

An expired token, one already used, or one presented for the wrong
platform receives a `404` error. An attempt with the wrong platform does
not consume the token. Consumption is atomic: two simultaneous requests
cannot create two devices.

### 2.3 Server guarantees

- lifetime: five minutes;
- single use;
- platform enforced;
- enrollment token stored only as an HMAC hash;
- automatic linking of the watch to the protected person;
- distinct durable credentials for phone and watch;
- alert deduplication by protected person + `clientAlertId`.

## 3. Client responsibilities

### Assisted person's phone

- offer "Connect the watch" only after the phone is registered;
- choose the correct platform without letting the user change it;
- request a new enrollment on each attempt;
- transmit `enrollmentToken` and `expiresAt` via the official local
  channel;
- never persist the ephemeral token beyond the flow;
- display waiting, success, expiration, and retry states;
- never transmit its own `deviceToken`.

### Watch

- accept only an enrollment message coming from the associated app;
- verify platform and expiration before the network call;
- call `/claim` immediately;
- store `deviceId` and `deviceToken` in native secure storage;
- confirm success to the phone without sending back `deviceToken`;
- retain the credentials after a restart;
- cleanly replace invalid credentials during a new enrollment;
- never log the enrollment token or the device token.

### Recommended storage

| Platform | Durable secret | Non-sensitive data |
| --- | --- | --- |
| watchOS | Extension Keychain | `deviceId`, schema version, enrollment date |
| Wear OS | Android Keystore + encrypted storage | `deviceId`, schema version, enrollment date |
| iOS | Existing Keychain | no durable enrollment token |
| Android | Existing Keystore/secure storage | no durable enrollment token |

## 4. Local enrollment transport

### watchOS

The phone creates the token, then sends it with `WCSession.sendMessage`
if the watch is reachable. `transferUserInfo` serves as a fallback
before expiration.

Proposed message:

```json
{
  "type": "companionEnrollment",
  "schemaVersion": 1,
  "platform": "watchos",
  "enrollmentToken": "<token>",
  "expiresAt": "2026-07-25T10:05:00+00:00"
}
```

The production URL must come from the application's signed
configuration, not from the received message. A development URL can
remain an explicit build option.

The watch replies only with:

```json
{
  "type": "companionEnrollmentResult",
  "schemaVersion": 1,
  "status": "enrolled"
}
```

### Wear OS

The phone uses `MessageClient` for the immediate path and requires
exactly one connected watch. It refuses to send a secret if zero or
multiple nodes are present, to avoid the wrong watch consuming the
token.

A short-lived durable `DataClient` fallback can be added with the Wear
OS consumer. It will need to unambiguously target the expected watch and
remove the item after success or expiration.

## 5. Minimal UX

Phone state:

```text
Watch not connected
→ Connecting
→ Watch connected
```

Recoverable errors:

- watch out of range: keep the screen open and allow "Retry";
- expired token: automatically create a new token;
- no Internet on the watch: keep the "Connection pending" state, then
  create a new token when the watch regains a network path;
- credentials already present: display "Watch connected" and offer an
  explicit reconnection;
- phone change: allow a new enrollment without duplicating incidents,
  thanks to the stable identity.

Do not display the raw token to the user. No QR code is necessary as
long as the phone and watch use their native pairing channel.

## 6. Recommended breakdown of upcoming PRs

### PR A — phone orchestration

- ✅ add an enrollment-creation API client to the assisted person app;
- ✅ add the "Connect the watch" action and states;
- ✅ transmit the versioned message to watchOS and Wear OS;
- ✅ add Flutter tests and build the native bridges;
- ✅ do not yet include direct alert submission.

### PR B — watchOS consumption

- receive the enrollment message;
- call `/claim` with `URLSession`;
- store the credentials in Keychain;
- confirm success to the iPhone;
- cover success, expiration, malformed input, restart, and missing
  secret.

### PR C — Wear OS consumption

- receive the message via the Data Layer;
- call `/claim` with a native HTTPS client;
- store the secret via Android Keystore;
- confirm success to the phone;
- cover the same cases as watchOS.

### PR D — direct watchOS transport

- persistent queue of incidents and cancellations;
- authenticated HTTPS with watch credentials;
- direct and relay launched with the same `clientAlertId`;
- resumption after network loss or restart.

### PR E — direct Wear OS transport and native Android relay

- persistent queue on the watch side;
- direct HTTPS;
- native Android reception independent of Flutter;
- resumption after a killed process or restart.

## 7. Enrollment acceptance criteria

| Scenario | Expected result |
| --- | --- |
| Protected phone + associated watch | Watch receives its own credentials |
| Caregiver attempts an enrollment | `422` rejection |
| Token used twice | First consumption succeeds, second rejected |
| Expired token | New token created without technical intervention |
| Incorrect platform | Rejection without consuming the token |
| Two simultaneous claims | Only one watch created |
| Phone or watch restarts after success | Connected state preserved |
| Secret missing or corrupted | Reconnection offered, no false success |
| Application logs inspected | No secret present |
| Watch re-enrolled | New usable identity, incidents still deduplicated by person |

## 8. Out of scope for enrollment

Enrollment does not yet guarantee:

- direct submission of a fall from the watch;
- native relay when Flutter is not running;
- offline resumption;
- revocation of a lost watch;
- server-side display of the companion device list;
- automatic rotation of the durable token.

These items remain separate increments. Revocation will need to be
addressed before a commercial release.
