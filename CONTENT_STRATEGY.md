# Fall Guardian — Build in Public Content Strategy

This file captures how to talk publicly about Fall Guardian as the project evolves.

## Positioning

The strongest angle for Fall Guardian is:

- personal problem
- real technical product
- safety-critical constraints
- honest tradeoffs
- lessons learned in public

The project should be presented as:

- a serious fall-detection product under construction
- built because existing options were not good enough
- shaped by real platform limitations and real-world testing

## Platform strategy

Use each platform for a different purpose:

- `LinkedIn`: French posts, builder story, product reasoning, engineering lessons, architecture decisions
- `X`: English posts, shorter build-in-public updates, screenshots, blockers, tradeoffs, quick lessons

Language rule:

- `LinkedIn` posts must be written in French
- `X` posts must be written in English

## What makes a good post

The best updates are not generic “progress updates”.

They are:

- milestone reached
- problem discovered
- decision made
- lesson learned
- next step identified

Use this recurring structure:

1. What changed
2. What problem appeared
3. What decision was made
4. What comes next

## Tone

The voice should feel like:

- an experienced engineer
- pragmatic
- low-ego
- direct
- calm
- technically serious

The intended posture is:

- “old guard”
- “boring tech because it works”
- “nothing to prove”
- no startup-founder performance
- no fake inspiration

Good traits:

- restrained
- concrete
- matter-of-fact
- honest about tradeoffs
- willing to say “this was a bad idea” or “this part is not production-grade yet”

Good phrasing patterns:

- “Je pensais que X. En pratique, Y.”
- “Ça paraissait simple. Ça ne l’était pas.”
- “J’ai changé d’avis sur ce point.”
- “The simple version was not robust enough.”
- “I’d rather use something boring that I can trust.”
- prefer language that sounds like notes from an experienced engineer, not personal-branding copy

Avoid:

- corporate storytelling
- motivational tone
- exaggerated “journey” language
- hype words like `game-changing`, `excited`, `super proud`, `incredible`
- fake vulnerability written like marketing copy

## Recommended cadence

- `LinkedIn`: one strong post every 1 to 2 weeks
- `X`: 2 to 4 shorter posts per week

Do not post every tiny commit.
Post when there is a real story, tradeoff, or lesson.

## Core content categories

Build content around four repeating categories:

- `Progress`
- `Problem`
- `Decision`
- `Lesson`

This keeps the narrative authentic and sustainable.

## Recurring themes

Good moments to publish:

- first working prototype
- first real-device validation
- first backend architecture milestone
- first major UX correction
- first cross-platform parity issue
- first reliability/security hardening step
- first major product pivot
- first caregiver-flow milestone
- first release/distribution milestone

## Suggested milestone posts

### 1. First working prototype

**LinkedIn angle**

“J’ai maintenant un premier prototype fonctionnel de Fall Guardian : la montre détecte la chute, le téléphone démarre une alerte synchronisée de 30 secondes, et l’alerte peut être annulée avant l’escalade.

La partie intéressante n’est pas l’interface. Le vrai sujet, c’est de garder la montre et le téléphone alignés sur le même timestamp au lieu de faire confiance à deux timers locaux.

Ce projet me rappelle surtout qu’une application de sécurité, c’est d’abord de la gestion d’état, des cas limites, et des modes de panne.

Prochaine étape : valider tout ça sur de vrais appareils, pas seulement sur émulateur.”

**X angle**

“First real prototype working:
- watch detects fall
- phone becomes an alert surface
- shared 30s countdown
- cancel from either side

The hard part is sync and state, not UI.”

### 2. First real-device validation

**LinkedIn angle**

“Les vrais appareils ont rapidement remis un peu d’ordre dans mes hypothèses.

Les simulateurs étaient utiles pour avancer, mais le flux réel montre/téléphone a fait apparaître immédiatement des problèmes de timing, de connectivité et d’UX qui n’étaient pas évidents avant.

Sur ce type d’application, ‘ça marche sur simulateur’ n’est pas une validation.

La suite est simple : durcir le flux d’alerte, documenter les modes de panne, puis seulement continuer à ajouter des fonctionnalités.”

**X angle**

“Real-device testing > simulator confidence.

The app behaves differently once you deal with:
- actual Bluetooth / Wear connectivity
- background state
- notification behavior
- real latency

A safety app has to be tested where it actually lives.”

### 3. Local SMS is not production-grade

**LinkedIn angle**

“Un des constats les plus clairs jusqu’ici : l’envoi de SMS en local n’est pas une architecture sérieuse à long terme pour ce type d’application.

En prototype, surtout sur Android, c’est tentant.
En pratique, ça pose vite des problèmes :
- platform differences
- weak observability
- poor auditability
- limited reliability

Je m’oriente donc vers une escalade pilotée par le backend, au lieu de considérer le téléphone comme moteur final de notification.

C’est plus de travail, mais c’est aussi une architecture plus propre.”

**X angle**

“I thought ‘send SMS after 30s’ would be enough.

It isn’t.

Good prototype idea, weak production architecture.

I’m shifting to backend-owned escalation because reliability matters more than shortcut implementations.”

### 4. Caregiver app vs SMS

**LinkedIn angle**

“J’ai passé du temps à évaluer le SMS comme canal principal d’alerte, et j’ai fini par changer d’avis.

La direction qui me paraît plus solide à long terme est plutôt :
- protected-person app
- caregiver app
- backend-owned push notifications
- optional Android SMS fallback only if explicitly enabled

Pourquoi : meilleure UX, meilleure observabilité, coût plus faible à long terme, et moins de dépendance au comportement des opérateurs.

C’est un choix produit, mais aussi un choix d’architecture.”

**X angle**

“Big product pivot:
I’m leaning toward caregiver app + push notifications instead of SMS-first.

Reason:
- cheaper
- richer UX
- better delivery tracking
- easier to scale cleanly

SMS may stay as optional Android fallback, not the core design.”

### 5. Safety UX is harder than detection

**LinkedIn angle**

“Je me rends compte que la détection de chute n’est que la moitié du sujet.

L’autre moitié, c’est l’UX de sécurité :
- can the user cancel quickly?
- is the alert readable under stress?
- does the phone show the right thing in foreground and background?
- does the flow fail clearly instead of pretending success?

Au fond, une application de sécurité, c’est surtout une machine à états avec une interface par-dessus.”

**X angle**

“The more I work on this, the more I think:
fall detection is not the hardest part.

The hard part is:
- alert state
- cancel behavior
- background handling
- failure handling
- user trust”

### 6. Cross-platform parity

**LinkedIn angle**

“Un des sujets les plus difficiles ici n’est pas l’algorithme de détection lui-même, mais la parité entre plateformes.

La promesse produit est simple. Le comportement des plateformes ne l’est pas du tout.

iPhone, Android, Apple Watch et Wear OS se comportent différemment sur :
- background execution
- notifications
- messaging between watch and phone
- escalation constraints

Une bonne partie du travail consiste donc à garder le même résultat de sécurité, même si les plateformes ne jouent pas selon les mêmes règles.”

**X angle**

“Cross-platform mobile truth:
same feature != same implementation.

For this project I have to align:
- iPhone
- Android
- Apple Watch
- Wear OS

The product outcome must match even when the OS rules do not.”

### 7. Backend architecture milestone

**LinkedIn angle**

“J’ai maintenant introduit un backend dédié pour la persistance des alertes et leur escalade.

Ça change un point important dans le projet :
le téléphone n’est plus la seule source de vérité pendant une alerte.

Le backend m’apporte maintenant :
- idempotency
- delivery tracking
- auditability
- cleaner future expansion toward caregiver notifications

Pour ce type d’application, c’est une base nettement plus sérieuse qu’un design uniquement côté client.”

**X angle**

“The backend changed the project a lot.

Now I can treat alerts as real tracked events instead of just UI actions on the phone.

That gives me:
- persistence
- retries
- observability
- cleaner architecture”

### 8. Debug delivery tooling

**LinkedIn angle**

“J’ai ajouté une couche de livraison simulée pour tester le flux complet d’alerte sans envoyer de vrais messages à chaque fois.

Dit comme ça, ça paraît secondaire.
En pratique, c’est important :
de bons outils de debug permettent de valider un comportement de sécurité de manière répétable.

J’essaie de rendre le projet testable comme un système complet, pas seulement comme une suite d’écrans.”

**X angle**

“Added a fake delivery debug path.

That lets me test:
- alert submission
- backend persistence
- worker flow
- delivery recording

without paying for real sends every time.”

### 9. CI and production hardening

**LinkedIn angle**

“Je passe aussi du temps sur la partie moins visible du projet : CI, scans de sécurité, builds Docker, et outillage qualité côté backend.

Ce n’est pas le genre d’avancement qui impressionne beaucoup vu de l’extérieur, mais c’est indispensable si l’application doit devenir fiable.

Un produit orienté sécurité ne peut pas se contenter de ‘ça marche sur ma machine’.”

**X angle**

“This week was less feature work, more hardening:
- CI
- Docker checks
- static analysis
- security scans
- production image cleanup

Not flashy, but necessary.”

### 10. Caregiver app announcement

**LinkedIn angle**

“La prochaine étape produit importante, c’est d’ajouter une vraie expérience dédiée aux aidants.

L’idée n’est plus de traiter les alertes comme de simples messages, mais de permettre aux aidants :
- receive alerts
- acknowledge them
- see location and context
- respond more clearly than with plain SMS

Ça me paraît être la bonne direction pour quelque chose qui doit être fiable, compréhensible et maintenable.”

**X angle**

“Next major step: caregiver app.

That’s where the project starts moving from a prototype alert tool to a more complete safety product.”

## Problem-focused post ideas

Especially good topics:

- What simulators hid from me
- Why I’m moving away from SMS-first
- Why a safety app is really a state machine
- The UX issue that only appeared on a real Android device
- Why backend ownership matters for alerts
- The cross-platform assumption that turned out to be false
- What I changed after testing with a real watch
- Why I now think this should become two apps, not one

## Tone guidance

The strongest tone for this project is:

- personal
- technical
- concrete
- honest
- understated
- not marketing-heavy

Good phrasing patterns:

- “I thought X. Real testing showed Y.”
- “This looked simple. It wasn’t.”
- “I changed my architecture because...”
- “Here’s the tradeoff I accepted.”
- “Je pensais que X. En pratique, Y.”
- “Ça paraissait simple. Ça ne l’était pas.”
- “J’ai changé d’avis sur ce point.”

Avoid:

- generic startup language
- exaggerated announcements
- progress posts with no real substance
- anything that sounds like corporate personal branding

## Best practical format

For each meaningful step:

- `LinkedIn`: 120 to 250 words, one screenshot or short carousel
- `X`: one short main post plus 1 to 3 reply posts with details, screenshots, or lessons

Default language split:

- `LinkedIn`: French
- `X`: English

## Workflow for future posts

Each time you work on the project, derive posts from:

- the milestone reached
- the new problem discovered
- the decision made
- the lesson learned
- the next step

If there is no clear problem, decision, or lesson, do not force a post.
