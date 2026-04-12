# Fall Guardian — Workflow complet

Ce document décrit exactement ce qui se passe sur chaque appareil dans chaque situation.

---

## Table des matières

1. [Comportement idéal (source de vérité produit)](#1-comportement-idéal-source-de-vérité-produit)
2. [Toujours actif : détection des chutes](#2-toujours-actif--détection-des-chutes)
3. [Chute détectée — Application téléphone au premier plan](#3-chute-détectée--application-téléphone-au-premier-plan)
4. [Chute détectée — Téléphone en arrière-plan ou écran verrouillé](#4-chute-détectée--téléphone-en-arrière-plan-ou-écran-verrouillé)
5. [Chute détectée — Application téléphone tuée](#5-chute-détectée--application-téléphone-tuée)
6. [Alerte active — L'utilisateur annule sur le téléphone](#6-alerte-active--lutilisateur-annule-sur-le-téléphone)
7. [Alerte active — L'utilisateur annule sur la montre](#7-alerte-active--lutilisateur-annule-sur-la-montre)
8. [Alerte active — 30 secondes écoulées (escalade backend)](#8-alerte-active--30-secondes-écoulées-escalade-backend)
9. [Synchronisation des réglages : téléphone → montre](#9-synchronisation-des-réglages--téléphone--montre)
10. [Cas limites et protections](#10-cas-limites-et-protections)

---

## 1. Comportement idéal (source de vérité produit)

Le comportement idéal de Fall Guardian est le suivant :

1. La détection de chute tourne en continu sur la montre, pas sur le téléphone.
2. Une chute crée un seul événement d'alerte avec un timestamp unique partagé par tous les appareils.
3. La montre affiche immédiatement une alerte plein écran avec haptique et un compte à rebours de 30 secondes.
4. Le téléphone devient toujours une surface d'alerte :
   - si l'application est au premier plan, affichage immédiat de `FallAlertScreen`
   - sinon, affichage systématique d'une notification système prioritaire
5. Le téléphone et la montre doivent toujours afficher le même temps restant car ils calculent le décompte à partir du même timestamp de chute.
6. L'annulation depuis n'importe quel appareil doit arrêter immédiatement l'alerte sur tous les autres appareils.
7. Une annulation reçue d'un autre appareil ne doit jamais être renvoyée en boucle au périphérique source.
8. Si les 30 secondes expirent sans annulation, l'alerte est escaladée exactement une fois.
9. L'escalade soumet l'alerte au backend, qui devient l'unique propriétaire de la notification des aidants liés au profil protégé, avec position GPS si disponible.
10. La direction produit cible est une application dédiée pour les aidants, alimentée par des notifications push backend-owned.
11. Android peut conserver un envoi SMS local uniquement comme fallback explicite, pas comme mécanisme principal du produit.

### Pourquoi les notifications push plutôt que le SMS

Trois raisons cumulatives ont conduit à ce choix :

**Raison économique** : les passerelles SMS tierces (Twilio, etc.) sont payantes à l'usage. Chaque alerte envoyée a un coût direct. Les notifications push FCM (Android) et APNs (iOS) sont gratuites, quel que soit le volume.

**Raison technique iOS** : Apple ne permet pas à une application d'envoyer un SMS en silence. Sur iOS, `flutter_sms` ouvre obligatoirement la feuille de composition Messages native — l'utilisateur doit confirmer l'envoi manuellement. Si la personne est à terre ou inconsciente, personne ne confirme. Le SMS ne part jamais. C'est un échec silencieux dans le cas exactement prévu par le produit.

**Raison produit** : le SMS est unidirectionnel et sans état. Il n't y a aucune traçabilité (livré ? lu ? acquitté ?), aucune coordination entre plusieurs aidants, et aucune surface pour une application dédiée. Les notifications push permettent de piloter une vraie expérience aidant : écran d'alerte active, acquittement, historique, arrêt des relances quand quelqu'un répond.
12. Si le backend n'est pas joignable ou refuse l'alerte, l'application doit l'indiquer clairement et enregistrer l'échec au lieu de signaler un faux succès.
13. Les réglages de sensibilité modifiés sur le téléphone sont appliqués immédiatement sur la montre, ou mis en file d'attente si la montre est hors ligne.
14. Les permissions critiques ne doivent jamais échouer silencieusement.
15. L'historique doit refléter fidèlement ce qu'il s'est passé : annulation, alerte envoyée, échec d'envoi, absence de destinataires, etc.
16. Les différences entre plateformes ne doivent pas changer le résultat de sécurité attendu.
17. L'alerte téléphone doit être pilotée par une machine à états explicite, pas par la seule durée de vie d'un écran.
18. Les transitions de cette machine à états doivent être testées directement au niveau service.

Le reste de ce document décrit l'implémentation actuelle visée pour atteindre ce comportement.

## 2. Toujours actif : détection des chutes

La détection des chutes tourne en permanence sur la montre. Le téléphone n'est pas impliqué à cette étape.

### Apple Watch (watchOS)

`FallDetectionManager.start()` est appelé dès que la ContentView apparaît (`onAppear → viewModel.startIfNeeded()`). Ensuite :

- `CMMotionManager` diffuse les données de l'accéléromètre à **50 Hz** (un échantillon toutes les 20 ms)
- Chaque échantillon passe dans `FallAlgorithm.processSample(ax, ay, az, nowMs)`
- L'algorithme fait tourner une machine à états à 3 phases (voir section 2 pour les détails)
- `WatchSessionManager.shared.startSession()` active la WCSession pour permettre l'envoi de messages

Il n'y a pas de service persistant en arrière-plan sur watchOS. L'application utilise `WKExtendedRuntimeSession` (stocké en tant qu'AnyObject pour éviter un import de framework) afin de demander un temps d'exécution étendu lorsqu'une alerte est active.

Un observateur UserDefaults (clés `thresh_*`) permet à `FallDetectionManager` de recharger les seuils sans redémarrage dès que le téléphone pousse de nouveaux réglages.

### Galaxy Watch (Wear OS)

`FallDetectionService` est un **service de premier plan** Android démarré dans `MainActivity.onCreate()`. Il tourne indéfiniment jusqu'à un arrêt manuel :

- Acquiert un `PARTIAL_WAKE_LOCK` (le CPU reste actif même quand l'écran s'éteint)
- Enregistre un `SensorEventListener` sur `TYPE_ACCELEROMETER` à `SENSOR_DELAY_GAME` (≈50 Hz)
- Affiche une notification persistante "Fall Guardian Active" (obligatoire par Android pour les services de premier plan)
- Au redémarrage de l'appareil : `BootReceiver` intercepte `ACTION_BOOT_COMPLETED` et relance le service

Un `SharedPreferences.OnSharedPreferenceChangeListener` écoute les changements de clés de seuils. Quand le téléphone pousse de nouveaux seuils, `PhoneMessageListenerService` les écrit dans SharedPreferences et le listener reconstruit le `FallAlgorithm` sans redémarrer le service.

### Algorithme de détection des chutes (identique sur les deux plateformes)

L'algorithme cherche une **signature en 3 phases** dans les données de l'accéléromètre :

```
Phase 1 — Chute libre
  Condition : magnitude de la force G < 0,5g  ET  maintenue pendant ≥ 80 ms
  Effet     : active freeFallQualifiedLatch = true

Phase 2 — Impact
  Condition : magnitude de la force G > 2,5g  APRÈS  freeFallQualifiedLatch activé
  Effet     : active impactActive = true  (reste actif pendant 2 secondes)

Phase 3 — Inclinaison  (informatif uniquement, ne fait pas partie du déclencheur)
  Condition : angle de l'appareil > 45°
  Effet     : suivi mais n'affecte pas le déclencheur

Déclencheur = freeFallQualifiedLatch ET impactActive
```

Points clés :
- Un **filtre passe-bas** (`alpha = 0,8`) isole la gravité de l'accélération brute pour calculer l'inclinaison à partir de la composante filtrée
- **L'ordre des phases est imposé** : l'impact ne compte que si la chute libre est venue en premier. Un choc soudain seul (poser brusquement le téléphone sur une table) ne déclenche rien
- **Délai de recharge de 5 secondes** après chaque détection pour éviter les déclenchements répétés d'un même incident

Quand l'algorithme se déclenche :
- watchOS : `FallDetectionManager` appelle `WatchSessionManager.shared.sendFallEvent(timestamp)` et déclenche le callback `onFallDetected` vers le ViewModel
- Wear OS : `FallDetectionService.onSensorChanged` appelle `WearDataSender.sendFallEvent(context, nowWall)`

---

## 3. Chute détectée — Application téléphone au premier plan

« Au premier plan » signifie que l'application téléphone est l'application active à l'écran.

### Côté montre (identique pour les deux plateformes)

1. L'algorithme se déclenche → capture `timestamp = System.currentTimeMillis()` (epoch Unix, ms)
2. L'algorithme se réinitialise (verrou effacé, minuteur d'impact réinitialisé)
3. **L'interface de la montre bascule vers l'AlertScreen** : fond rouge sombre, grand chiffre du décompte
4. Le retour haptique démarre : légère vibration toutes les secondes au-dessus de 10s, forte vibration toutes les secondes en dessous de 10s
5. **Message envoyé au téléphone :**
   - *watchOS* : `WCSession.sendMessage(["event": "fall_detected", "timestamp": timestamp])` — temps réel, Bluetooth/Wi-Fi
   - *Wear OS* : `MessageClient.sendMessage(nodeId, "/fall_event", Long sur 8 octets)` — via la couche de données Wearable

### Côté téléphone — iOS

`WatchSessionManager.session(_:didReceiveMessage:)` se déclenche sur un thread WCSession en arrière-plan :

1. `resetCancelContext()` — efface tout état d'annulation résiduel d'une alerte précédente, arrête la boucle de surveillance d'annulation depuis la montre
2. `showFallNotification(timestamp:)` — poste immédiatement une `UNNotificationRequest` via `UNUserNotificationCenter`
   - `interruptionLevel = .timeSensitive` (iOS 15+) — contourne les modes de concentration
   - Comme l'app est au premier plan : `AppDelegate.userNotificationCenter(_:willPresent:)` se déclenche et retourne `[.banner, .sound]` — **la bannière s'affiche par-dessus l'application même si elle est au premier plan**
3. `forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])` — dispatché sur le thread principal
4. `channel.invokeMethod("onFallDetected", ...)` — Dart le reçoit dans `WatchCommunicationService`
5. `startPollingForWatchCancel()` — démarre la boucle de détection d'annulation (simulateur : fichier `/tmp` ; appareil réel : vérification `applicationContext`)

Côté Dart (`main.dart._onFallDetected`) :
1. Plateforme iOS → on passe `NotificationService.showFallDetectedNotification()` (la native l'a déjà postée)
2. `_navigatorKey.currentState?.push(MaterialPageRoute(FallAlertScreen(...)))` — pousse l'écran d'alerte avec `fullscreenDialog: true` (animation de glissement vers le haut)

### Côté téléphone — Android

`WearDataListenerService.onMessageReceived` se déclenche dans un processus en arrière-plan (le service écouteur) :

1. Le chemin est `/fall_event` → analyse un `ByteBuffer` de 8 octets pour extraire `timestamp: Long`
2. Valide que le message provient d'un nœud Wearable connecté (rejette les messages falsifiés)
3. Appelle `handleFallDetected(timestamp)`
4. `MainActivity.getInstance()?.isInForeground` est **true** → appelle `activity.sendFallDetectedToFlutter(timestamp)` directement, retourne immédiatement

`MainActivity.sendFallDetectedToFlutter(timestamp)` :
1. **Vérification de déduplication** : si `timestamp == lastForwardedTimestamp`, abandon silencieux (empêche la double alerte)
2. `lastForwardedTimestamp = timestamp`
3. `runOnUiThread` : annule la notification native de réveil (ID 2), appelle `channel.invokeMethod("onFallDetected", ...)`

Côté Dart (`main.dart._onFallDetected`) :
1. Plateforme Android → `NotificationService().showFallDetectedNotification(...)` — affiche une notification heads-up (redondant au premier plan, mais inoffensif)
2. Pousse `FallAlertScreen`

### Comportement de FallAlertScreen (identique sur les deux plateformes)

Une fois poussé :
- `initState()` appelle `_setupPulse()` (animation de pulsation de 800ms sur l'icône d'avertissement), `_startCountdown()`, et s'abonne au `cancelStream`
- `_startCountdown()` déclenche un `Timer.periodic(500ms)` :
  - À chaque tick : `remaining = (30 - (now - fallTimestamp) / 1000).clamp(0, 30)`
  - Met à jour la couleur de l'anneau de progression (orange → rouge à ≤10s)
  - Quand `remaining == 0` : annule le timer, appelle `_sendAlert()`
- `PopScope(canPop: false)` — geste de retour désactivé
- **Seulement trois façons de quitter cet écran** : appuyer sur Annuler, recevoir une annulation externe via `cancelStream`, ou laisser le décompte atteindre zéro

---

## 4. Chute détectée — Téléphone en arrière-plan ou écran verrouillé

« En arrière-plan » signifie que l'utilisateur a appuyé sur Accueil (l'app est en mémoire mais non visible). « Écran verrouillé » signifie que le téléphone est en veille.

### Côté montre

Identique à la section 2 — la montre ne distingue pas l'état du téléphone.

### Côté téléphone — iOS

WCSession livre le message à `WatchSessionManager` quel que soit l'état de l'application (l'OS accorde un bref temps d'exécution à l'app en arrière-plan) :

1. `resetCancelContext()`
2. `showFallNotification(timestamp:)` — poste une `UNNotification` native
   - L'app n'est **pas** au premier plan → iOS affiche la bannière dans le centre de notifications / sur l'écran verrouillé automatiquement (aucun delegate nécessaire)
   - `interruptionLevel = .timeSensitive` traverse les modes de concentration
3. `forwardToFlutter("onFallDetected", ...)` — le moteur Flutter EST en cours d'exécution (app en arrière-plan, pas tuée) → l'appel au channel réussit
4. Flutter `_onFallDetected` se déclenche → ne re-poste PAS la notification (iOS uniquement) → pousse `FallAlertScreen`

**Écran verrouillé** : puisque la notification se déclenche, iOS affiche la bannière sur l'écran verrouillé. L'utilisateur peut appuyer sur la notification pour remettre l'app au premier plan et voir le `FallAlertScreen` déjà rendu.

**Note** : `WatchSessionManager` s'enregistre pour les notifications Darwin au démarrage (`registerDarwinFallEventObserver`). Dans le simulateur, si le processus est suspendu, la notification Darwin (`CFNotificationCenterGetDarwinNotifyCenter`) le réveille immédiatement.

### Côté téléphone — Android

`WearDataListenerService` est démarré par le système dans un processus séparé — il tourne même quand l'app est en arrière-plan ou l'écran verrouillé :

1. `handleFallDetected(timestamp)` — `activity.isInForeground` est **false** (ou l'activité est null)
2. Appelle `showFallNotification(timestamp)` :
   - Crée/s'assure que le canal `fall_guardian_alerts` existe
   - Construit une `NotificationCompat` avec :
     - `PRIORITY_HIGH`, `CATEGORY_ALARM`
     - `setOngoing(true)` — ne peut pas être rejetée par un glissement
     - `setContentIntent(pendingIntent)` — appuyer sur la bannière lance `MainActivity` avec l'extra `fall_timestamp`
     - `setFullScreenIntent(pendingIntent, true)` — sur un écran verrouillé/en veille, cela se lance en tant qu'**activité plein écran** (comme un appel entrant), allumant l'écran — requiert `USE_FULL_SCREEN_INTENT` (accordé automatiquement avant Android 14 ; sur Android 14+ vérifié via `canUseFullScreenIntent()`)
3. Appelle aussi `activity?.sendFallDetectedToFlutter(timestamp)` — si l'activité est en vie mais en arrière-plan, le décompte Flutter **démarre immédiatement** (le chronomètre SMS tourne même si l'utilisateur ne tape jamais sur la notification)

Quand l'utilisateur **appuie sur la notification** :
- `MainActivity.onNewIntent(intent)` se déclenche avec l'extra `fall_timestamp`
- Appelle `sendFallDetectedToFlutter(timestamp)` → **la vérification de dédup** le rejette (déjà transmis à l'étape 3)
- Aucun second `FallAlertScreen` n'est poussé

---

## 5. Chute détectée — Application téléphone tuée

« Tuée » signifie que le processus est complètement disparu (l'utilisateur l'a balayé, ou l'OS l'a arrêté pour libérer de la mémoire).

### Côté montre

Identique. La montre ne connaît pas et ne se soucie pas de l'état du processus du téléphone.

### Côté téléphone — iOS

Quand `sendMessage` échoue (téléphone inaccessible), l'app watchOS bascule sur `transferUserInfo`. Cela met le dictionnaire en file d'attente dans le système de transfert en arrière-plan de WCSession.

iOS fait alors :
1. **Lance l'app en arrière-plan** — `application(_:didFinishLaunchingWithOptions:)` se déclenche
2. `WatchSessionManager()` est créé tôt, `startSession()` est appelé
3. WCSession s'active → `session(_:didReceiveUserInfo:)` se déclenche → délègue à `session(_:didReceiveMessage:)`
4. `showFallNotification(timestamp:)` — poste une `UNNotification` native → visible sur l'écran verrouillé / dans le centre de notifications
5. `forwardToFlutter(...)` — le channel est `nil` (le moteur Flutter n'est pas encore initialisé lors d'un lancement en arrière-plan)
6. `forwardToFlutter` stocke le `timestamp` dans `UserDefaults["pendingFallTimestamp"]`
7. **`didInitializeImplicitFlutterEngine` ne se déclenche PAS** lors des lancements en arrière-plan uniquement — le moteur Flutter n'est pas démarré

L'app reste suspendue en arrière-plan. La notification native est la seule chose visible pour l'utilisateur.

Quand l'**utilisateur appuie sur la notification et ouvre l'app** :
1. UIScene s'active → le moteur Flutter s'initialise → `didInitializeImplicitFlutterEngine` se déclenche
2. `watchSession?.setChannel(channel!)` — injecte le channel maintenant prêt
3. `watchSession?.drainPendingFallEvent()` :
   - Lit `UserDefaults["pendingFallTimestamp"]`
   - Supprime la clé (empêche une seconde vidange au prochain lancement)
   - Supprime la notification de réveil du centre de notifications
   - Appelle `forwardToFlutter("onFallDetected", ...)` — réussit maintenant car le channel existe
4. Flutter `_onFallDetected` se déclenche → `FallAlertScreen` est poussé

**Important** : le décompte est calculé à partir du `fallTimestamp` original, pas à partir de « maintenant ». Si 12 secondes se sont écoulées entre la chute et l'ouverture de l'app par l'utilisateur, il verra 18 secondes restantes — la montre et le téléphone sont toujours parfaitement synchronisés.

### Côté téléphone — Android

`WearDataListenerService` est un `WearableListenerService` enregistré dans `AndroidManifest.xml`. Android le démarre en arrière-plan automatiquement même quand le processus de l'app est tué.

1. `handleFallDetected(timestamp)` — `MainActivity.getInstance()` retourne `null` (activité non en cours)
2. `showFallNotification(timestamp)` — poste la notification full-screen intent (identique au cas arrière-plan)
3. `activity?.sendFallDetectedToFlutter(timestamp)` — ne fait rien (activité null)

Quand l'**utilisateur appuie sur la notification** :
1. `MainActivity` se lance de zéro
2. `configureFlutterEngine()` tourne
3. L'intent contient l'extra `fall_timestamp` → `sendFallDetectedToFlutter(timestamp)` est appelé
4. Le moteur Flutter est prêt → `channel.invokeMethod("onFallDetected", ...)` → `FallAlertScreen` poussé

**Décompte toujours synchronisé** : même logique — `FallAlertScreen` calcule `remaining = 30 - elapsed` à partir du timestamp original.

---

## 6. Alerte active — L'utilisateur annule sur le téléphone

L'utilisateur appuie sur le bouton **"Je vais bien – Annuler"** sur le `FallAlertScreen`.

### Téléphone (Flutter — les deux plateformes)

`_cancel()` s'exécute :

1. `_timer?.cancel()` — arrête immédiatement le timer de décompte de 500ms
2. `setState(() => _dismissed = true)` — empêche `_sendAlert` de s'exécuter même si un tick résiduel se déclenche
3. `WatchCommunicationService.sendCancelAlert()` — best-effort, non attendu :
   - *iOS* : `channel.invokeMethod("sendCancelAlert")` → `AppDelegate` → `WatchSessionManager.sendCancelAlert()`
   - *Android* : `channel.invokeMethod("sendCancelAlert")` → `MainActivity.sendCancelAlertToWatch()`
4. `FallEventsRepository().add(FallEvent(status: cancelled))` — journalise l'événement
5. `NotificationService().cancelAll()` — supprime toute notification OS persistante
6. `Navigator.of(context).pop()` — retourne à l'écran d'accueil

### Côté montre — iOS (réception de l'annulation)

`WatchSessionManager.sendCancelAlert()` côté téléphone :
1. Met `alertCancelledFlag = true` — les futurs sondages `query_cancel_status` obtiennent une réponse immédiate
2. `stopPollingForWatchCancel()` — annule la Task de surveillance d'annulation de la montre
3. Simulateur : écrit `/tmp/com.fallguardian.cancelAlert`
4. Appareil réel : `WCSession.sendMessage(["event": "alert_cancelled"])` — livraison immédiate
5. Aussi `transferUserInfo` + `updateApplicationContext(["alertCancelled": true])` — fallbacks redondants

Sur l'Apple Watch, `WatchSessionManager.session(_:didReceiveMessage:)` reçoit `"alert_cancelled"` :
- Déclenche le callback `onAlertCancelled` sur le thread principal
- `ContentViewModel.cancelAlert(notifyPhone: false)` — `notifyPhone: false` empêche de renvoyer au téléphone
- `isAlertActive = false` → SwiftUI redessine vers l'IdleScreen
- Les retours haptiques s'arrêtent

### Côté montre — Wear OS (réception de l'annulation)

`MainActivity.sendCancelAlertToWatch()` :
1. Obtient les nœuds Wearable connectés
2. Envoie `MessageClient.sendMessage(nodeId, "/cancel_alert", payload)`

Sur la Galaxy Watch, `PhoneMessageListenerService.onMessageReceived` reçoit `/cancel_alert` :
- Appelle `WearDataSender.cancelAlertFromPhone()` :
  - `handler.removeCallbacks(tickRunnable)` — arrête le timer de décompte
  - `alertActive = false` — Compose recompose vers l'IdleScreen
  - N'appelle PAS `sendCancelAlert()` en retour (évite le ping-pong)

---

## 7. Alerte active — L'utilisateur annule sur la montre

L'utilisateur appuie n'importe où sur l'AlertScreen de la montre.

### Côté montre — watchOS

`ContentView.onTapGesture` → `viewModel.cancelAlert(notifyPhone: true)` :

1. `alertExpireTask?.cancel()` — annule la Task Swift du décompte
2. `stopPollingForPhoneCancel()` — annule la Task de surveillance d'annulation
3. `isAlertActive = false` — SwiftUI redessine vers l'IdleScreen
4. Puisque `notifyPhone: true` : `WatchSessionManager.shared.sendCancelAlert()`

`WatchSessionManager.sendCancelAlert()` :
1. Simulateur : écrit `/tmp/com.fallguardian.cancelFromWatch` ; le côté iOS sonde toutes les 1s
2. Appareil réel : `WCSession.sendMessage(["event": "alert_cancelled"])` + fallback `transferUserInfo` + `updateApplicationContext(["alertCancelled": true])`

### Côté montre — Wear OS

`WearDataSender.sendCancelAlert(context)` :
1. `handler.removeCallbacks(tickRunnable)` — arrête le décompte
2. `alertActive = false` — Compose redessine vers l'IdleScreen
3. `sendToPhone("/cancel_alert", tableau d'octets vide)`

### Côté téléphone (réception de l'annulation — les deux plateformes)

*iOS* : `WatchSessionManager.session(_:didReceiveMessage:)` reçoit `"alert_cancelled"` :
- `forwardToFlutter("onAlertCancelled", nil)` → `channel.invokeMethod("onAlertCancelled")`

*Android* : `WearDataListenerService.onMessageReceived` sur le chemin `/cancel_alert` :
- `MainActivity.getInstance()?.sendCancelAlertToFlutter()`
- `channel.invokeMethod("onAlertCancelled", null)` sur le thread UI

Côté Dart (`main.dart._onAlertCancelled`) :
- `_cancelAlertController.add(null)` — pousse un événement dans le stream de diffusion

`FallAlertScreen._cancelSub` reçoit l'événement du stream :
- Appelle `_cancel()` — même flux qu'à la section 5 **sauf** étape 3 : `sendCancelAlert()` est quand même appelé vers la montre, mais comme la montre a déjà annulé c'est un no-op (WCSession le rejette ou la montre ignore un `alert_cancelled` dupliqué)

---

## 8. Alerte active — 30 secondes écoulées (escalade backend)

Le tick de `FallAlertScreen._timer` se déclenche quand `remaining == 0` :

1. Timer annulé immédiatement (empêche un double appel)
2. `_dismissed` et `_sending` vérifiés — abandon si déjà traité
3. L'interface bascule en **mode envoi** : l'anneau de décompte disparaît, un spinner apparaît

### Étape A : Obtenir le GPS

`LocationService().getCurrentPosition()` :
1. Vérifie `Geolocator.isLocationServiceEnabled()` — si désactivé, retourne null
2. Vérifie la permission (`LocationPermission`) :
   - `denied` → `requestPermission()`
   - `deniedForever` → retourne null
3. `Geolocator.getCurrentPosition(desiredAccuracy: high, timeLimit: 10s)`
4. Retourne `Position?` (lat/lng) ou null en cas d'échec

### Étape C : Charger les destinataires locaux connus

`ContactsRepository().getAll()` lit le stockage sécurisé du téléphone et désérialise le JSON. Si la clé n'existe pas ou est malformée, retourne une liste vide.

Note produit :
- l'implémentation actuelle repose encore sur des contacts d'urgence côté téléphone et un backend à sémantique SMS
- la direction cible est de remplacer ce modèle par des aidants liés au backend et une application aidant dédiée

### Étape D : Soumettre l'alerte au backend

`BackendApiService().submitFallAlert(...)` :

1. **Garde contacts vides** : si aucun contact → retourne `[]` immédiatement
2. S'assure que le téléphone possède une identité backend (`device_id` + `device_token`) et l'enregistre si nécessaire
3. Resynchronise les contacts d'urgence vers `PUT /api/v1/emergency-contacts`
4. Envoie `POST /api/v1/fall-alerts` avec :
   - `clientAlertId`
   - `fallTimestamp`
   - `locale`
   - `latitude` / `longitude`
5. Le backend persiste l'événement, met en file l'escalade, puis renvoie un accusé de réception
6. Le téléphone traite cet accusé comme une escalade acceptée et journalise les noms de contacts locaux comme destinataires attendus

### Étape E : Persister dans l'historique

```
FallEvent(
  id: UUID,
  timestamp: DateTime.fromMillisecondsSinceEpoch(fallTimestamp),
  status: alertSent  (si notified.isNotEmpty)
       OU alertFailed (si des destinataires existaient mais le backend n'a pas accepté l'alerte),
  latitude: position?.latitude,
  longitude: position?.longitude,
  notifiedContacts: ["Alice", "Bob", ...]
)
```
`FallEventsRepository().add(event)` ajoute à la liste JSON dans `SharedPreferences["fall_events"]`.

### Étape F : Nettoyage

1. `NotificationService().cancelAll()` — supprime la notification OS du centre de notifications
2. **La montre n'est PAS explicitement notifiée** à ce stade. Le décompte sur la montre atteindra 0 de façon indépendante et son `alertExpireTask` déclenchera `isAlertActive = false`, fermant son propre écran. Il n'y a pas de message "escalade envoyée" vers la montre.
3. L'interface affiche le résultat pendant 2s (succès) ou 5s (échec), puis `Navigator.pop()` → écran d'accueil

---

## 9. Synchronisation des réglages : téléphone → montre

L'utilisateur ouvre l'**écran des réglages** sur le téléphone, ajuste les curseurs, appuie sur **Sauvegarder**.

### Téléphone

`SettingsScreen._save()` :
1. Écrit les 4 seuils dans `SharedPreferences`
2. Appelle `WatchCommunicationService.pushThresholds(freeFall, impact, tilt, freeFallMs)`
3. `channel.invokeMethod("sendThresholds", {"thresh_freefall": 0.5, ...})`

### Android → Wear OS

`MainActivity` reçoit `sendThresholds` :
1. Construit un payload JSON depuis la map
2. `Wearable.getNodeClient(this).connectedNodes` → pour chaque nœud : `MessageClient.sendMessage(nodeId, "/thresholds", jsonBytes)`

`PhoneMessageListenerService` sur la montre reçoit `/thresholds` :
1. Parse le JSON
2. Écrit chaque clé dans `SharedPreferences`
3. `FallDetectionService.prefChangeListener` se déclenche (tourne sur le thread du service)
4. Reconstruit `FallAlgorithm` avec les nouveaux seuils — **pas de redémarrage du service nécessaire**

Si la montre est **déconnectée** quand on appuie sur Sauvegarder : `connectedNodes` retourne une liste vide, les seuils ne sont pas envoyés. Ils seront re-poussés la prochaine fois que le téléphone les envoie (ex: prochain lancement de l'app ou prochaine sauvegarde) — il n'y a actuellement pas de mécanisme de mise en file d'attente pour les pushes de seuils manqués.

### iOS → watchOS

`AppDelegate` reçoit `sendThresholds` :
1. `WatchSessionManager.sendThresholds(args)`
2. Si `WCSession.isReachable` : `sendMessage(...)` — immédiat
3. Si non joignable : `transferUserInfo(...)` — mis en file, livré au réveil de la montre

Sur l'Apple Watch, `WatchSessionManager.session(_:didReceiveMessage:)` reçoit `"set_thresholds"` :
1. Lit le dictionnaire `thresholds`
2. Écrit dans `UserDefaults`
3. L'observateur `FallDetectionManager` (`UserDefaults.didChangeNotification`) se déclenche
4. Reconstruit `FallAlgorithm` — **pas de redémarrage nécessaire**

---

## 10. Cas limites et protections

### Chute pendant une alerte active (< 5s de cooldown)

Le **cooldown de 5 secondes** dans `FallDetectionManager` / `FallDetectionService` empêche un second `sendFallEvent` dans les 5 secondes suivant le premier. Si l'utilisateur roule/rebondit après une chute, l'algorithme peut se déclencher à nouveau mais le cooldown le rejette silencieusement.

### Deux alertes consécutives (> 5s d'intervalle)

Si une seconde chute est détectée pendant que `FallAlertScreen` est encore visible :
- Un second `FallAlertScreen` serait poussé par-dessus le premier
- Le `_dismissedFlag` du premier écran le protège — mais les deux écrans partagent le `cancelStream`. Une annulation les fermera tous les deux via le stream de diffusion
- En pratique, le cooldown de 5 secondes puis l'alerte déjà en cours rendent cela très improbable

### Garde de déduplication (cas Android arrière-plan)

`WearDataListenerService` appelle `sendFallDetectedToFlutter(timestamp)` immédiatement (pour démarrer le décompte) et affiche aussi une notification. Si l'utilisateur appuie sur la notification, `onNewIntent` se déclenche avec le même timestamp. `MainActivity.lastForwardedTimestamp` bloque le doublon, donc un seul `FallAlertScreen` est jamais poussé par événement de chute.

### Montre déconnectée lors d'une chute

- *Wear OS* : `MessageClient` déclenche son listener d'échec silencieusement. Le décompte de la montre continue et atteint 0 sans que le téléphone le sache. Aucune escalade backend n'est soumise.
- *watchOS* : `sendMessage` échoue → `transferUserInfo` est mis en file. Quand le Bluetooth se reconnecte, le téléphone reçoit l'événement (potentiellement plusieurs secondes plus tard). `FallAlertScreen` affichera un décompte déjà partiellement ou totalement écoulé — il calcule à partir du timestamp original, donc `remaining` peut être 0 immédiatement, déclenchant `_sendAlert()` aussitôt.

### Téléphone hors de portée — iOS / watchOS

`sendMessage` échoue silencieusement. `transferUserInfo` persiste la file sur la montre. Quand le téléphone revient à portée, la livraison se produit. Si le téléphone était tué, le chemin de vidange UserDefaults gère cela (section 4). Si le téléphone était en arrière-plan, `session(_:didReceiveUserInfo:)` se déclenche normalement.

### Aucun destinataire configuré

Le flux d'escalade vérifie qu'au moins un destinataire local connu existe avant soumission. `FallAlertScreen` journalise un `FallEvent(status: alertFailed)` sans destinataire notifié. L'utilisateur voit le message d'échec pendant 5 secondes.

### GPS indisponible ou permission refusée

`LocationService` retourne `null`. Le corps du SMS utilise la chaîne localisée "Localisation : indisponible". L'événement est quand même journalisé — `latitude` et `longitude` sont null. L'historique ne montre aucune coordonnée pour cet événement.

### Limite de débit SMS déclenchée

Si `sendFallAlert` est appelé dans les 60 secondes d'un envoi réussi précédent, il retourne `[]` immédiatement. Cela est traité comme un envoi échoué : statut `alertFailed`, message d'erreur 5 secondes, aucun SMS envoyé. La limite de 60 secondes survit aux redémarrages de l'app (stockée dans `SharedPreferences`).

### iOS — conflit de delegate flutter_local_notifications

`flutter_local_notifications` s'empare du `UNUserNotificationCenterDelegate` lors de l'initialisation sur iOS. Cela supprime toute notification qu'il n'a pas postée lui-même — y compris notre notification native de chute.

**Correction** : `NotificationService.initialize()` passe complètement `_plugin.initialize()` sur iOS. `AppDelegate` se définit comme `UNUserNotificationCenterDelegate` permanent dans `application(_:didFinishLaunchingWithOptions:)` avant qu'un plugin puisse le revendiquer. `NotificationService.showFallDetectedNotification()` n'est jamais appelé sur iOS (protégé par `if (!Platform.isIOS)`). Toutes les notifications iOS passent par `WatchSessionManager.showFallNotification()` et `UNUserNotificationCenter` directement.

### Android — `USE_FULL_SCREEN_INTENT` sur Android 14+

Sur Android 14, `USE_FULL_SCREEN_INTENT` est devenu une permission accordable à l'exécution. `WearDataListenerService.showFallNotification` vérifie `nm.canUseFullScreenIntent()` avant d'appeler `setFullScreenIntent()`. Si la permission n'a pas été accordée, la notification s'affiche comme une bannière heads-up haute priorité plutôt que comme une alerte plein écran.

### Android — vérification de sécurité `isTrustedIntent`

`MainActivity` ne traite les extras d'intent `fall_timestamp` que s'ils proviennent du même package. Cela empêche une application malveillante de construire un `Intent` avec un faux timestamp et de forcer une fausse alerte de chute sur le téléphone de l'utilisateur.

---

## Tableau comparatif des plateformes

| Situation | watchOS | Wear OS | iOS téléphone | Android téléphone |
|-----------|---------|---------|---------------|-------------------|
| Détection active | CMMotionManager + runtime étendu | Service premier plan + WakeLock | — | — |
| Chute détectée | AlertScreen + sendMessage | AlertScreen + MessageClient | — | — |
| Téléphone premier plan | ← envoie l'événement → | ← envoie l'événement → | FallAlertScreen | FallAlertScreen |
| Téléphone arrière-plan | ← envoie l'événement → | ← envoie l'événement → | Notif native + FallAlertScreen (arrière-plan) | Notif plein écran + FallAlertScreen (arrière-plan) |
| Téléphone tué | transferUserInfo mis en file | Service démarre MainActivity | notif au réveil, vidange à l'ouverture | notif, intent au tap |
| Annulation téléphone | ← sendCancelAlert → | ← sendCancelAlert → | FallAlertScreen fermé | FallAlertScreen fermé |
| Annulation montre | IdleScreen | IdleScreen | FallAlertScreen fermé | FallAlertScreen fermé |
| Timeout | IdleScreen (auto-fermeture) | IdleScreen (auto-fermeture) | SMS envoyé | SMS envoyé |
| Envoi SMS | — | — | Feuille Messages (confirmation utilisateur) | SmsManager silencieux |
| Seuils reçus | UserDefaults + reconstruction | SharedPreferences + reconstruction | — | — |
