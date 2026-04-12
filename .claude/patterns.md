# Fall Guardian Patterns

Use these patterns as generic guidance. Always prefer nearby repository examples when they exist.

Design intent:

- apply SOLID principles without adding unnecessary abstraction
- keep coordinator-driven workflow readable
- use native platform or API Platform features directly when they already solve the need cleanly
- choose readability over premature optimization
- write code that is easy for a human reviewer to understand

## Flutter Coordinator-Owned Workflow

- `AlertCoordinator` owns alert lifecycle, timeout, cancel propagation, and escalation
- widgets render state and trigger actions; they do not own timers or delivery side effects
- repositories own persistence; services/adapters own runtime integrations

## Native Bridge Pattern

- native phone/watch code receives platform events
- bridge validates and translates them into shared app events
- platform adapters do not duplicate Flutter workflow decisions

## Backend Command Flow

- API Platform resource/processor or controller receives request
- application service validates and orchestrates
- persistence happens explicitly
- Messenger worker handles slow outbound delivery

## Test Selection

- coordinator or repository change -> Flutter unit/widget test
- Android/iOS/watch runtime change -> platform test or at least targeted manual verification note
- backend delivery or API behavior change -> backend unit/integration test

## Cross-Platform Contract Rule

- new event/method/key/config must be checked across Flutter, Android, iOS, Wear OS, watchOS, and backend when relevant
- avoid adding local-only assumptions that break shared fall timestamp or cancel behavior
