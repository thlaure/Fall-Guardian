# Fall Guardian — Remaining Implementation Work

This file captures what still remains to implement after the repository was redirected toward the agreed target architecture:

- protected-person app
- caregiver app
- backend-owned push notifications
- Android local SMS only as optional fallback

## Current baseline

What already exists:

- protected-person app in [`flutter_app/`](/Users/thomaslaure/Documents/projects/fall_guardian/flutter_app)
- caregiver app scaffold in [`caregiver_app/`](/Users/thomaslaure/Documents/projects/fall_guardian/caregiver_app)
- Symfony backend in [`backend/`](/Users/thomaslaure/Documents/projects/fall_guardian/backend)
- current alert flow already reaches the backend
- docs now reflect the two-app direction

What this means in practice:

- the structural direction is correct
- the real caregiver product flow is not implemented yet

## What still has to be implemented

### 1. Backend domain model

The backend is still built around:

- `Device`
- `EmergencyContact`
- `FallAlert`
- `SmsAttempt`

It needs to move toward:

- `ProtectedPerson`
- `Caregiver`
- `CaregiverLink`
- `ProtectedDevice`
- `CaregiverDevice`
- `FallAlert`
- `PushAttempt`
- `AlertAcknowledgement`

This is the main architectural gap.

### 2. Caregiver identity and linking

The product still needs a real linking model:

- who the protected person is
- who the caregivers are
- how they are linked

An explicit product decision is still needed for the linking flow:

- invite code
- pairing token
- QR code
- email invitation
- phone-number-based linking

Without this, the caregiver app cannot do real work.

### 3. Push notification delivery

The backend is still SMS-shaped.

It still needs:

- caregiver device token registration
- push provider integration
  - FCM
  - APNs path if needed via FCM or a backend abstraction
- push worker flow
- push attempt persistence
- delivery status model

### 4. Caregiver app actual features

The caregiver app still needs:

- onboarding / login or linking flow
- device push token registration
- list of linked protected people
- active alert screen
- alert detail screen
- acknowledge action
- resolved / handled state
- history view

At the moment it is only a shell.

### 5. Protected-person app product changes

The current `flutter_app` still behaves like a contact-based app.

It still needs:

- caregiver management flow instead of emergency contacts
- invite / link UI
- optional fallback settings for Android SMS
- wording cleanup in screens and repositories, not only localization
- history model aligned with alert delivery rather than SMS semantics everywhere

### 6. Backend API redesign

Current endpoints are still contact-oriented:

- `/api/v1/emergency-contacts`
- `/api/v1/fall-alerts`

Future backend endpoints likely need to include:

- caregiver link / invite creation
- caregiver link acceptance
- caregiver device registration
- caregiver alert read model
- caregiver alert acknowledge endpoint

### 7. Alert acknowledgement flow

A real caregiver workflow needs:

- caregiver receives alert
- caregiver opens it
- caregiver acknowledges it
- backend records acknowledgement
- protected-person side can reflect acknowledgement later if needed

That loop does not exist yet.

### 8. Real notification behavior

The push flow still needs validation for:

- app in foreground
- app in background
- locked phone
- killed app
- multiple caregiver devices
- multiple caregivers
- duplicate suppression
- late delivery handling

### 9. Optional Android SMS fallback

If Android SMS is kept:

- it should be explicit
- Android-only
- not the main architecture
- ideally secondary fallback, not primary delivery

The policy and code path for that are not finished.

### 10. Backend migration path

There is still a transition problem:

- current backend schema is contact/SMS oriented
- target schema is caregiver/push oriented

So a migration plan is still needed:

- keep current contact model temporarily
- add caregiver model beside it
- migrate protected-person app from contacts to caregivers
- retire SMS-specific backend entities later

### 11. Real-device validation

The final architecture still needs real-device validation for:

- Android phone + Galaxy Watch + backend
- iPhone + Apple Watch + backend
- caregiver app receiving push on real devices

Until this is done, the architecture is not truly validated.

## Recommended implementation order

If continuing from here, the recommended order is:

1. **Backend caregiver model**
   - add protected person / caregiver / link entities
   - keep current alert model temporarily

2. **Caregiver app registration**
   - device token registration
   - placeholder linked-account state

3. **Protected-person caregiver management**
   - replace contact CRUD with caregiver linking flow

4. **Push delivery**
   - backend sends caregiver notifications instead of SMS as primary path

5. **Caregiver alert UI**
   - active alert screen
   - acknowledge action

6. **Optional Android SMS fallback**
   - add only after the push path exists

## Short summary

The repo is now pointed in the correct direction structurally, but the core caregiver product still remains to be built:

- caregiver identity
- caregiver linking
- push notifications
- caregiver app behavior
- acknowledgement flow
- backend domain migration

Current state:

- architecture direction set
- second app scaffolded
- production caregiver path not implemented yet
