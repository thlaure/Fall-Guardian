# Audit — détection de chute

Date de lecture du code : 1er novembre 2026. Base : `main` à `c4a12d7`.
Aucun seuil, aucune transition de l'automate et aucun capteur n'a été modifié.
Les mesures de la section 1.6 viennent du harness ajouté dans ce changement ;
elles portent sur des traces synthétiques, pas sur des chutes réelles.

Trois statuts sont utilisés partout :

- **Fait** : comportement lu dans un fichier, ou résultat d'un test nommé.
- **Interprétation** : conséquence directe de ces faits.
- **Hypothèse** : explication plausible, non mesurée sur des personnes.

## 1. Fonctionnement actuel

### 1.1 Deux produits, un seul automate dans le dépôt

**Fait.** Le dépôt contient un automate identique dans son intention, écrit deux fois :

- Wear OS : `apps/wear_os/app/src/main/java/com/fallguardian/FallAlgorithm.kt`
- watchOS : `apps/watchos/FallGuardian/FallGuardian Watch App/FallAlgorithm.swift`

**Fait.** En production, seul Wear OS exécute cet automate. Sur watchOS, `ContentViewModel.startIfNeeded` appelle `FallDetectionManager.shared.stop()` et le commentaire dit que seule l'API système d'Apple produit les alertes (`ContentView.swift` lignes 236-238). `applyDetectionMode` rappelle `stop()` dans tous les états d'autorisation (lignes 441-442). `FallDetectionManager.start()` n'a aucun appelant dans l'application. La recherche du symbole ne le trouve que dans sa définition et dans un commentaire de `WatchSessionManager.swift`.

**Fait.** Le téléphone Flutter ne lit pas d'accéléromètre pour décider d'une chute. Il reçoit un événement montre, puis crée l'alerte API.

**Interprétation.** Régler les quatre seuils du téléphone change la détection sur une montre Wear OS. Sur Apple Watch, ces seuils ne participent pas à la décision : l'écran de réglages ne les affiche d'ailleurs que si `Platform.isAndroid` (`apps/assisted_mobile/lib/screens/settings_screen.dart` ligne 32). La qualité de détection iPhone est celle de Fall Detection d'Apple, plus le relais Fall Guardian.

### 1.2 Acquisition Wear OS

**Fait.** Un seul capteur est enregistré : `Sensor.TYPE_ACCELEROMETER` (`FallDetectionService.kt` lignes 165 et 252-256). Aucune inscription de gyroscope, de magnétomètre, de baromètre, de fréquence cardiaque, ni de détecteur « montre portée ». La recherche de `TYPE_GYROSCOPE`, `OFF_BODY` et `HEART` dans `apps/wear_os/**/*.kt` ne remonte que l'accéléromètre (et des types audio sans rapport).

**Fait.** La période demandée est 40 000 µs, donc 25 Hz, avec une latence de lot de 500 000 µs (`FallDetectionService.kt` lignes 140-144 et 252-256). Le commentaire des lignes 140-141 dit que 25 Hz fournit quatre échantillons pour la fenêtre de 160 ms. L'horodatage utilisé par l'automate est celui du capteur, `event.timestamp / 1_000_000`, pas l'heure d'arrivée du lot (lignes 269-273).

**Fait.** Les échantillons sont en m/s² (lignes 280-284). L'automate les convertit en g en divisant par `9.81f` (`FallAlgorithm.kt` lignes 86 et 210-212).

**Fait.** Le service est un foreground service de type `health` (`AndroidManifest.xml` lignes 43-46), relancé au boot (`BootReceiver`). Aucun wake lock n'est pris pendant la surveillance (`FallDetectionService.kt` lignes 76-79 et 167-173). Un `PARTIAL_WAKE_LOCK` n'existe que pour l'alerte en cours, plafonné à 35 s (ligne 145). Le manifeste déclare `HIGH_SAMPLING_RATE_SENSORS` (ligne 8) ; 25 Hz est en dessous du régime que cette permission vise sur Android récent.

**Fait.** `Sensor.getMaximumRange()` n'est pas lu. La fréquence réellement livrée n'est pas comparée à 25 Hz. `isWakeUpSensor` est seulement écrit dans le journal de diagnostic (ligne 258).

**Interprétation.** Le dessin batterie est explicite : pas de wake lock permanent, réveils CPU groupés par lots de 500 ms, service foreground pour rester éligible à l'exécution. Le coût de ce dessin est reporté sur la fidélité des pics et sur la continuité en veille profonde.

**Hypothèse.** Sur une montre dont l'accéléromètre n'est pas un capteur de réveil, le SoC en suspend profond peut cesser de livrer des échantillons malgré le foreground service. Le code ne l'empêche pas. Le battement de diagnostic toutes les 30 s ne tient pas de wake lock (lignes 109-110), donc une absence de battement montre que le CPU a dormi, pas que les échantillons ont continué.

**Hypothèse.** Si la pleine échelle du capteur est inférieure ou égale à 4 g, le seuil d'impact par défaut de 4,2 g est inatteignable et le détecteur ne part jamais. Rien dans le code ne le signale.

### 1.3 Automate Wear OS

**Fait.** Défauts, bornés ensuite par les préférences (`FallDetectionService.kt` lignes 230-233) :

| Paramètre | Défaut | Borne |
| --- | --- | --- |
| `freeFallThresholdG` | 0,35 g | 0,1–1,0 |
| `impactThresholdG` | 4,2 g | 1,5–5,0 |
| `tiltThresholdDeg` | 80° | 20–90 |
| `freeFallMinMs` | 160 ms | 40–200 |

Constantes non réglables (`FallAlgorithm.kt` lignes 44-50) : filtre `alpha = 0,8` par échantillon ; fenêtre candidat 5 000 ms ; écart max entre fin de phase basse et impact 1 500 ms ; attente avant immobilité 300 ms ; immobilité 2 000 ms ; seuil dynamique d'immobilité 0,25 g ; tolérance `|‖a‖ − 1 g|` 0,25 g.

**Fait.** `processSample` ne renvoie `true` que si les trois verrous sont vrais en même temps (lignes 151-155) :

1. phase basse qualifiée (`‖a‖ < 0,35 g` pendant au moins 160 ms, et cette qualification date de moins de 1 500 ms au moment de l'impact) ;
2. impact (`‖a‖ > 4,2 g`) ;
3. changement d'orientation d'au moins 80° entre le vecteur de gravité figé à l'impact et le vecteur filtré courant ;
4. puis 2 000 ms d'immobilité continue après les 300 ms d'attente.

Le point 4 est la condition `stillnessQualified`, pas un verrou séparé. L'orientation et la phase basse sont des verrous : une fois pris, ils restent vrais jusqu'à `clearCandidate` ou `reset`. L'immobilité, elle, se remet à zéro à chaque échantillon qui sort du critère (lignes 141-149).

**Fait.** Les commentaires du service disent autre chose. Lignes 71-73 et 286-288 de `FallDetectionService.kt` : l'impact plus « either qualified low acceleration or an orientation change », puis l'immobilité. `docs/SYSTEM_OVERVIEW.md` lignes 194-195 répète ce OU. L'automate exige le ET. Les libellés téléphone sont alignés sur le ET (`app_localizations_fr.dart` lignes 132-135).

**Fait.** La gravité est un passe-bas `g ← 0,8 g + 0,2 a`, mis à jour sur tout échantillon dont la norme est inférieure ou égale au seuil d'impact (lignes 113-117 et 173-178). La phase de faible accélération met donc le filtre à jour. Le vecteur « avant impact » est l'état de ce filtre au moment du pic, pas un instantané pris au début de la chute. Les pics au-dessus du seuil d'impact sont exclus du filtre. `alpha` ne dépend pas de l'intervalle de temps.

**Fait.** Si la norme du vecteur avant impact ou du vecteur courant est inférieure à `0,01` (en m/s², pas en g), l'angle renvoyé est 0 (lignes 187-188). La copie Swift compare à `0,01` sur une magnitude déjà exprimée en g (`FallAlgorithm.swift` lignes 55 et 150). Les deux fichiers n'ont pas le même plancher.

**Fait.** Après une détection expédiée, le service fait `algorithm.reset()` et impose 5 s de silence (`FallDetectionService.kt` lignes 100 et 310-312). Le téléphone reçoit un timestamp, pas la trace (`WearDataSender`).

**Interprétation.** Quatre échantillons à 25 Hz couvrent 120 ms (trois intervalles de 40 ms), pas 160 ms. Le verrou de phase basse s'arme sur l'échantillon dont l'horodatage vaut au moins `début + 160 ms`, donc le cinquième échantillon si le premier a armé le chronomètre. Un motif dont le dernier échantillon encore sous 0,35 g est à +120 ms, et dont l'échantillon suivant est déjà l'impact, ne qualifie pas la phase basse. Le commentaire « four samples for the default 160 ms window » est faux au sens de l'inégalité codée.

**Interprétation.** À 25 Hz, la constante de temps du filtre est −0,04 / ln(0,8) ≈ 179 ms. Le gain de la direction d'avant la chute après n échantillons bas vaut 0,8ⁿ. Après 21 échantillons (800 ms), il reste environ 0,9 % de la direction initiale : la référence d'orientation est devenue la direction de la phase basse. Après 31 échantillons à zéro, la norme tombe sous 0,01 m/s² et l'angle est forcé à 0 pour tout le reste du candidat.

**Interprétation.** L'immobilité est une porte d'entrée de l'alerte, pas une escalade après l'alerte. Une personne qui bouge dans les 2 s qui suivent l'impact, ou dont un seul échantillon sort de la bande ±0,25 g, ne déclenche rien. Le compte à rebours de 30 s ne commence qu'après cette porte.

**Interprétation.** Les tests historiques de `FallAlgorithmTest.kt` avancent le temps de 20 ms par défaut (ligne 304), soit l'équivalent de 50 Hz. Ils ne voient ni le pas de 40 ms demandé en production, ni un filtre dont `alpha` est par échantillon. Le scénario nominal à 20 ms peut passer alors qu'un pas de 40 ms sur le même geste échoue, et l'inverse est vrai pour la constante de temps du filtre.

### 1.4 Ce que le harness a mesuré sur des traces synthétiques

**Fait.** `FallReplayTest.bundled corpus matches the current detector episode by episode` rejoue des CSV à 40 ms dans le vrai `FallAlgorithm`, avec le même reset et le même silence de 5 s que le service. Résultat sur les défauts actuels :

| Trace | Étiquette | Détection |
| --- | --- | --- |
| `qualified_low_phase_25hz` : phase basse jusqu'à +160 ms, impact 4,6 g, rotation 90°, repos | chute | oui, 2 320 ms après l'impact |
| `four_samples_low_phase_25hz` : dernier échantillon bas à +120 ms, puis impact | chute | non |
| `long_weightlessness_25hz` : ~1,2 s à 0 m/s², impact, rotation 90°, repos | chute | non |
| `sideways_low_phase_25hz` : 800 ms à 3 m/s² sur X (0,31 g), impact, repos sur X | chute | non |
| `table_knock_25hz` : impact sans phase basse, repos dans l'axe initial | ADL | non |
| `three_g_impact_25hz` : pic à 3 g, rotation, repos | ADL | non, et le pic ne compte pas comme impact |
| `device_drop_25hz` : ~200 ms à 0, pic à 8 g, rotation 90°, repos | ADL | oui |

**Fait.** Sur ce jeu, le harness calcule 1 vrai positif, 3 faux négatifs, 2 vrais négatifs, 1 épisode faux positif. Sensibilité 0,25 et spécificité 2/3 **sur ces sept clips**. Ce ne sont pas des chiffres cliniques. Les clips durent quelques secondes et sont des paliers constants, pas des chutes filmées.

**Fait.** `halving a 50 hertz stream can miss either the low phase or the impact` construit un pic unique de 60 m/s² (un échantillon de 20 ms) précédé d'une phase basse de 160 ms. Le flux à 20 ms est détecté. Garder un échantillon sur deux :

- phase paire : le pic est conservé, la phase basse observée s'arrête à +120 ms, pas de détection ;
- phase impaire : le pic disparaît (l'échantillon voisin est à 1,5 g), pas de détection ;
- max de chaque paire : le pic est conservé, la phase basse échoue quand même, pas de détection.

**Interprétation.** À 25 Hz, le détecteur peut manquer un pic court et peut aussi manquer une phase basse réelle de 160 ms selon l'alignement de la grille. Les deux pannes sont indépendantes. Moyenner ou prendre le max d'un créneau ne répare pas la porte des 160 ms.

### 1.5 Apple Watch

**Fait.** `SystemFallDetectionService` crée un `CMFallDetectionManager` (`FallGuardianApp.swift` lignes 229-233). Sur `didDetect`, tout événement dont `resolution != .rejected` envoie la notification locale et `sendFallEvent` (lignes 289-295). `confirmed`, `dismissed` et `unresponsive` suivent le même chemin. Le projet dit lui-même que le sens de ces quatre valeurs n'a pas été validé sur une montre physique (`docs/SYSTEM_OVERVIEW.md` lignes 185-186 et 541).

**Fait.** Le texte d'état « Apple background fall detection active » est affiché quand l'autorisation de l'application est `authorized` (`ContentView.swift` lignes 444-445). Aucun appel ne lit le mode système « Always on » ou « Only on during workouts ». Si l'autorisation est refusée ou si l'API est indisponible, le texte dit que la surveillance est inactive (lignes 447-449). Il n'y a pas de repli sur l'accéléromètre.

**Fait.** `apps/watchos/README.md` lignes 45-48 décrit encore les défauts 0,7 g, 2,5 g, 50°, 60 ms, et un OU entre orientation et phase basse. Le source Swift a les défauts 0,35 g, 4,2 g, 80°, 160 ms, et le ET (`FallAlgorithm.swift` lignes 11-14 et 120-124). Ce README décrit un détecteur qui n'est de toute façon pas démarré.

**Fait public, Apple.** La page support actuelle décrit un choc dur, une alerte immédiate, le choix « I'm OK » ou les secours, et une absence d'appel automatique tant que la montre voit du mouvement. Après environ une minute d'immobilité, un compte à rebours de 30 s précède l'appel et l'envoi de la position aux contacts d'urgence. La détection des poignets doit être active pour l'appel automatique. Apple écrit qu'elle ne détecte pas toutes les chutes et qu'une activité à fort impact peut déclencher l'alerte. Le réglage est « Always on » ou « Only on during workouts ». À partir de 55 ans la fonction s'active toute seule. Entre 18 et 55 ans, une Apple Watch neuve depuis watchOS 8.1 active par défaut la détection pendant les entraînements seulement. Sources : [Use Fall Detection with Apple Watch](https://support.apple.com/en-us/108896), [guide watchOS](https://support.apple.com/guide/watch/manage-fall-detection-apd34c409704/watchos).

**Fait public, Apple, 2018.** Le communiqué Series 4 décrit un accéléromètre et un gyroscope mesurant jusqu'à 32 g, une décision sur la trajectoire du poignet et l'accélération d'impact, une alerte que l'on peut écarter, puis l'appel si la montre constate 60 s d'immobilité. Source : [communiqué Apple du 12 septembre 2018](https://www.apple.com/newsroom/2018/09/redesigned-apple-watch-series-4-revolutionizes-communication-fitness-and-health/).

**Fait public, API.** `CMFallDetectionManager` réveille l'application en arrière-plan, notifie tous les événements de chute, et ne laisse qu'un court délai pour appeler le completion handler. L'entitlement `com.apple.developer.health.fall-detection` est requis. Source : [documentation Apple](https://developer.apple.com/documentation/coremotion/cmfalldetectionmanager).

**Interprétation.** Apple sépare la détection (alerte tout de suite) de l'immobilité (escalade vers les secours environ une minute plus tard). Fall Guardian sur Wear OS fait l'inverse pour l'immobilité : 2 s immobiles sont exigées avant même d'ouvrir la fenêtre de 30 s. Fall Guardian n'appelle pas les secours ; le projet le marque comme non fait (`SYSTEM_OVERVIEW.md` lignes 542-543). Sur Apple Watch, les deux chaînes coexistent : le SOS Apple, et le relais aidants de Fall Guardian.

**Hypothèse.** Un utilisateur de 18 à 55 ans qui n'a pas passé Fall Detection en « Always on » n'est pas surveillé en dehors des entraînements, alors que l'application peut afficher « active » dès que sa propre autorisation est accordée. À confirmer sur une montre : l'API tierce ne semble pas exposer ce mode, et le code ne le lit pas.

**Hypothèse, seconde main.** Un article de presse rapporte qu'Apple a constitué son jeu avec environ 2 500 personnes et 250 000 journées, sans cascadeurs. Ce n'est pas une publication vérifiable ici. Source secondaire : Indian Express, 2019, « Fall detection in Apple Watch Series 4 ». À ne pas citer comme une performance mesurée.

### 1.6 De la détection à l'aidant

**Fait.** Fenêtre locale de 30 s (`AlertCountdownPolicy.kt` ligne 3). Le serveur pose `cancel_deadline_at = received_at + 30 s` (`FallAlert.php` lignes 24 et 80-81), pas `fall_detected_at + 30 s`. L'aidant est notifié par un message Messenger retardé de la grâce restante (`AlertIngestionService`). L'annulation n'est acceptée que tant que le statut est encore recevable et que l'échéance n'est pas passée.

**Fait.** Wear OS envoie un timestamp. Le téléphone Android peut poster l'alerte sans Flutter (`NativeAlertRelay`, `detectionSource = wear_os`). L'iPhone a son propre relais (`NativeAppleWatchAlertRelay.swift`, `detectionSource = apple_watch`), distinct du `JobService` Android. Le commentaire Dart « iOS has no Android native relay » (`watch_communication_service.dart` ligne 171) vise l'absence de ce `JobService`, pas l'absence de tout envoi natif.

**Fait.** La position est lue après la création, en `LocationAccuracy.high`, avec 10 s de budget (`location_service.dart` lignes 43-47). Elle est stockée en `DOUBLE PRECISION` clair. `attachLocation` enregistre les coordonnées et ne réexpédie pas de push (`AlertIngestionService.php` lignes 110-120). Le push FCM n'inclut la latitude et la longitude que si elles sont déjà là au moment de l'envoi (`FcmPushGateway.php` lignes 48-53).

**Interprétation.** Un aidant qui ne lit que la notification peut ne jamais voir la position si le GPS arrive après le push. L'écran aidant, lui, relit l'API.

## 2. Faiblesses, par impact

L'impact est celui d'une chute manquée ou d'une alerte à tort pour une personne seule. L'ordre n'est pas celui de la facilité de correction.

### 1. Sur Apple Watch, Fall Guardian ne détecte pas

**Fait.** Section 1.1 et 1.5. La surveillance effective dépend de l'entitlement, de l'autorisation de l'application, et du réglage système qu'Apple documente (toujours, ou entraînements seulement, avec un défaut « entraînements » sous 55 ans). Le code ne distingue pas ces cas. Il n'y a pas de repli.

**Interprétation.** Pour la moitié des téléphones visés, le modèle, les seuils et les tests Kotlin/Swift ne protègent personne. Une autorisation accordée à l'application peut coexister avec une détection système éteinte ou limitée aux workouts. Le porteur voit « active ».

**Hypothèse.** `dismissed` correspond au « I'm OK » d'Apple. Si c'est le cas, Fall Guardian notifie quand même les aidants, puisque seul `.rejected` est ignoré. Le dépôt marque ce point comme non vérifié sur le matériel.

### 2. Les quatre portes en ET manquent des chutes que le produit veut couvrir

**Fait.** Impact par défaut 4,2 g. Le test historique `three g wrist impact followed by rest does not trigger conservative defaults` et la trace `three_g_impact_25hz` refusent 3 g. Phase basse minimale 160 ms sous 0,35 g. Orientation 80° du **poignet** par rapport à un vecteur déjà filtré. Immobilité continue de 2 s, rompue par un seul échantillon.

**Interprétation.** Une chute lente (syncope, glissade le long d'un mur) ne fournit souvent ni un passage durable sous 0,35 g ni un pic à 4,2 g. Une chute sur surface molle baisse le pic. Une chute où le bras ne tourne pas de 80° par rapport à l'avant-impact — bras le long du corps, ou bras qui amortit et revient — échoue à l'orientation même si le torse est au sol. Une personne consciente qui bouge après le choc échoue à l'immobilité. Ce sont les scénarios demandés (chute lente, surface molle, mur, mouvement résiduel). Le code les ferme par construction ; le taux réel n'est pas mesuré.

Kangas et al., *Gait & Posture*, 2008 (doi:10.1016/j.gaitpost.2008.01.003), sur accéléromètre taille / poignet / tête, chutes standardisées de trois adultes : à la taille ou à la tête, des seuils simples d'impact plus posture donnent 97–98 % de sensibilité et 100 % de spécificité dans ce laboratoire ; les auteurs concluent que le poignet n'est pas un site utilisable pour cette famille d'algorithmes. La posture du poignet ne décrit pas celle du torse. La thèse du même auteur (Oulu, 2011) donne, pour l'impact seul au poignet, une sensibilité de 32 à 75 % et une spécificité de 100 % sur ce petit jeu, et dit que la posture n'a pas été utilisée au poignet pour cette raison. Échantillon de laboratoire, pas une preuve sur le terrain.

Bagalà et al., *PLoS ONE*, 2012 (doi:10.1371/journal.pone.0037062) : 13 algorithmes publiés, surtout au tronc, réputés très sensibles sur chutes simulées, retombent à une sensibilité moyenne de 57 % (maximum 82,8 %) sur 29 chutes réelles. Sur une journée de trois sujets, les fausses alertes vont de 3 à 85. Ce n'est pas une mesure de Fall Guardian. C'est la raison de ne pas croire les tests à paliers.

### 3. Deux mécanismes du filtre produisent des faux négatifs même quand le geste « ressemble » au scénario nominal

**Fait.** Traces `four_samples_low_phase_25hz`, `long_weightlessness_25hz`, `sideways_low_phase_25hz` : non détectées, section 1.6. Le code qui l'explique est le filtre mis à jour pendant la phase basse, le plancher à 0,01 m/s², et l'inégalité `>= 160 ms` sur des échantillons espacés de 40 ms.

**Interprétation.** Une chute avec une vraie phase basse un peu longue, ou un bras qui change de direction pendant cette phase, efface la référence d'orientation que le commentaire prétend figer « immediately before impact » (`FallAlgorithm.kt` lignes 17-18). Le scénario nominal des tests (160 ms exactement à zéro, puis un palier à 90°) est un des rares motifs qui gardent la direction initiale.

### 4. 25 Hz, pleine échelle inconnue, pas de gyroscope

**Fait.** 25 Hz demandé, lots de 500 ms, pas de contrôle de pleine échelle, pas de gyroscope. Le test de décimation montre la perte d'un pic de 20 ms et l'échec de la porte 160 ms quand on passe de 20 ms à 40 ms.

**Interprétation.** Un impact au poignet est souvent plus court que 40 ms. À 25 Hz, le pic livré est soit un échantillon tombé sur la grille, soit une valeur déjà filtrée par le HAL. Le seuil 4,2 g est alors appliqué à une valeur atténuée. Apple documente une pleine échelle de 32 g et un gyroscope : la trajectoire du poignet est une rotation, pas seulement un changement de posture après le choc.

Saleh, Abbas et Le Bouquin Jeannès, *IEEE Sensors Journal*, 2021 (doi:10.1109/JSEN.2020.3018335) construisent FallAllD précisément parce que beaucoup de jeux publics sous-échantillonnent, saturent à ±2 g ou ±4 g, et ne couvrent pas le poignet. Leur accéléromètre poignet est à 238 Hz et ±8 g.

**Hypothèse.** Course, frappe, claquement de mains : le pic dépasse 4,2 g et la phase basse existe dans le balancer du bras. L'immobilité de 2 s et les 80° limitent ces faux positifs tant que le geste ne se termine pas par un repos dans une autre orientation. Un arrêt net après un choc peut passer. Non mesuré sur trace réelle. La trace `device_drop_25hz` montre seulement que la règle accepte chute libre + pic + rotation + repos, ce qu'une montre qui tombe et s'immobilise produit.

**Hypothèse.** Les cahots de voiture restent sous la combinaison 0,35 g pendant 160 ms, 4,2 g, 80° et 2 s immobiles. Risque de faux positif plus faible que le risque de chute manquée. À mesurer, pas à traiter en premier.

### 5. La documentation et les tests décrivent un autre détecteur

**Fait.** Commentaires service et `SYSTEM_OVERVIEW.md` : logique en OU. README watchOS : anciens seuils. Tests historiques : pas de 20 ms. Aucun test ne rejoue une trace datée, un export diagnostic, ni un jeu public.

**Interprétation.** On peut faire passer `make -C apps/wear_os test` et croire le détecteur validé. Les régressions qui comptent (pas de 40 ms, phase basse longue, référence d'orientation détruite) n'y étaient pas. Un prochain correctif peut « réparer » le OU décrit par le commentaire et élargir les faux positifs sans que le commentaire ait eu raison.

## 3. Améliorations, par impact / effort

Chaque gain se mesure avec le harness de la section 4. Aucun chiffre de sensibilité terrain n'existe aujourd'hui : le critère est le delta sur un corpus fixé, pas une impression.

### 1. Figer la gravité au début de la phase basse

**Changement.** Dans `updateGravity`, ne plus intégrer les échantillons tant que la phase basse est active. Conserver le vecteur d'avant la chute, celui qui est encore proche de 1 g. Continuer à ignorer les pics d'impact, comme aujourd'hui. Aligner le plancher d'orientation sur une norme en g, identique en Kotlin et en Swift.

**Pourquoi.** C'est le mécanisme des traces `long_weightlessness_25hz` et `sideways_low_phase_25hz`. Le commentaire du fichier décrit déjà l'intention ; le filtre fait autre chose. Effort : une condition et un test. Pas un nouveau modèle.

**Mesure.** Ces deux traces deviennent des vrais positifs. `table_knock_25hz`, `three_g_impact_25hz` et `four_samples_low_phase_25hz` restent négatives : ce correctif ne doit pas créer d'impact ni allonger une phase basse trop courte. Puis le même diff est rejoué sur le poignet FallAllD (section 4). On publie le delta de sensibilité et de fausses alertes par heure d'ADL, pas un pourcentage isolé.

### 2. Rendre la porte de 160 ms cohérente avec le pas réel

**Changement.** Décider explicitement, dans le code, ce qu'est une phase basse de 160 ms quand les échantillons sont espacés de 40 ms. Deux options propres : qualifier dès que l'intervalle entre le premier et le dernier échantillon bas, prolongé d'une demi-période, atteint 160 ms ; ou baisser le défaut à une valeur qui tombe sur la grille (120 ms) et l'écrire comme tel. Corriger le commentaire « four samples ». Faire dépendre `alpha` de `dt` (`alpha = exp(-dt / τ)` avec τ fixé, par exemple 180 ms) pour que 25 Hz et 50 Hz filtrent la même posture.

**Pourquoi.** La trace à quatre échantillons et le test de décimation montrent une porte qui dépend de la phase de la grille. Les tests à 20 ms masquent le défaut. Effort faible, localisé à `updateFreeFall` et au filtre.

**Mesure.** `four_samples_low_phase_25hz` a un résultat choisi et commenté, plus le test de décimation. Une même trace rejouée à 20 ms et à 40 ms avec le filtre en temps donne la même décision sur le scénario nominal. Avant / après sur FallAllD poignet rééchantillonné à 40 ms.

### 3. Dire ce qu'Apple Watch surveille vraiment

**Changement.** Le texte « active » ne doit être vrai que si l'on a dit au porteur que la détection est celle d'Apple, qu'elle dépend du mode toujours / entraînements, et qu'elle est indisponible sous 18 ans ou sans l'autorisation. Vérifier sur une Series réelle le `UserResolution` de « I'm OK », de la fermeture, et de l'absence de réponse ; ne relayer vers les aidants que les résolutions que le produit veut. Mettre le README watchOS au niveau du source, ou retirer l'automate Swift du chemin documenté tant que `start()` n'est pas appelé. Ne pas maintenir deux copies « au cas où » : elles ont déjà divergé sur le plancher d'orientation (0,01 m/s² contre 0,01 g).

**Pourquoi.** C'est le défaut le plus grave pour un client iPhone, et le correctif de communication est petit. Le correctif de résolution demande une montre, pas un nouveau modèle. Un automate maison ne remplace pas Apple hors de l'écran allumé : watchOS suspend l'accéléromètre dès que l'application passe en arrière-plan (`FallDetectionManager.swift` lignes 36-39).

**Mesure.** Liste écrite des résolutions observées sur la montre, et un test du relais qui refuse celles qui ne doivent pas créer d'alerte. Pas de métrique de sensibilité : le modèle n'est pas dans le dépôt.

### 4. Mesurer sur FallAllD poignet avant de toucher aux seuils

**Changement.** Pas de baisse du 4,2 g et pas de baisse des 80° tant que le corpus de la section 4 n'a pas été joué. Le 3 g est refusé aujourd'hui par test ; le relâcher augmente les faux positifs d'une quantité inconnue.

**Pourquoi.** C'est le plus grand levier de décision, et il ne change pas l'automate. Les seuils actuels ont été durcis (migration `fall_algorithm_version` 5, anciens défauts 2,5 g et 45–70°) sans jeu public dans le dépôt. Effort : conversion de fichiers, pas de la recherche.

**Mesure.** Sensibilité par type de chute (molle, mur, lente, avant, arrière, latérale — selon les identifiants d'activité du jeu), spécificité et fausses alertes par heure sur les ADL du même jeu, au poignet seulement. Deux rééchantillonnages à 40 ms : décimation et max du créneau. L'écart entre les deux est l'estimation de ce que 25 Hz coûte en pics.

### 5. Sortir les 2 s d'immobilité de la porte de détection

**Changement.** Ouvrir l'alerte locale et la grâce serveur sur le motif cinématique (phase basse, impact, orientation), une fois les points 1, 2 et 4 mesurés. Garder l'immobilité comme donnée d'escalade : par exemple un second état « toujours immobile » visible de l'aidant, ou un raccourcissement de la grâce. Ne pas copier les 60 s d'Apple tant que le produit n'appelle pas les secours. La grâce de 30 s existe déjà pour absorber un faux positif chez une personne consciente.

**Pourquoi.** Aujourd'hui, la personne qui tombe et se débat n'entre jamais dans cette grâce. Apple fait l'inverse : alerte d'abord, immobilité ensuite, et le dit publiquement. Kangas traite la posture après impact comme un critère de position, pas comme deux secondes sans un seul échantillon hors bande. Effort moyen : le taux de faux positifs va monter, et il faut le chiffre du point 3 avant de merger.

**Mesure.** Sur FallAllD poignet, sensibilité avec et sans la porte d'immobilité, et fausses alertes par heure d'ADL. Cible à fixer avant le changement, par écrit : par exemple ne pas descendre sous une spécificité donnée sur les ADL du jeu, ou accepter N fausses alertes par jour simulé si la sensibilité sur les chutes molles monte d'un delta fixé. Le delta compte, pas un objectif absolu inventé ici.

### 6. Enregistrer la fréquence livrée et la pleine échelle, sur la montre

**Changement.** Au `registerListener`, écrire `maximumRange`, la résolution, et `isWakeUpSensor` dans le journal déjà présent. Sur une session diagnostic, calculer la période médiane entre `sensor_elapsed_ms`. Refuser de surveiller, ou abaisser le seuil d'impact sous la pleine échelle, si `maximumRange` ne peut pas dépasser le seuil. Ne pas monter à 50 Hz tant que cette mesure n'est pas faite : avec un lot de 500 ms, le réveil CPU reste d'environ 2 Hz ; le coût réel est celui du hub capteur, pas celui du CPU.

**Pourquoi.** Le point 4 de la section 2 est une hypothèse tant qu'aucune montre n'a écrit sa pleine échelle. Effort faible, aucun changement de décision si la pleine échelle est large.

**Mesure.** Une session diagnostic portée, écran éteint, 30 minutes. Période médiane, pire trou, `maximumRange`. Si la médiane s'écarte de 40 ms ou si des trous dépassent la fenêtre de 160 ms, le 25 Hz nominal est un souhait.

### 7. Gyroscope, après les points 4 et 5

**Changement.** Enregistrer `TYPE_GYROSCOPE` au même horodatage, et ajouter une porte sur la vitesse angulaire pendant la phase basse et l'impact. Pas à la place de l'accéléromètre. Le baromètre est un mauvais candidat : les reprises publiques de FallAllD constatent qu'il bouge peu sur une chute à l'échelle d'une pièce (dépôts dérivés, pas une conclusion du papier original à prendre pour une mesure universelle).

**Pourquoi.** Apple décrit la trajectoire du poignet, donc la rotation. L'orientation par gravité filtrée arrive après le choc et ne suit pas le torse (Kangas). Effort plus haut : batterie, synchronisation des deux flux, retouche de l'automate, second canal dans le harness. Le faire avant le chiffre accéléromètre seul du point 4 mélange les causes.

**Mesure.** À sensibilité égale sur FallAllD poignet, baisse des fausses alertes par heure d'ADL. Le jeu contient le gyroscope à 238 Hz, ±2 000 °/s.

## 4. Évaluation déterministe

Le harness est en place. Il ne modifie pas `FallAlgorithm`.

| Fichier | Rôle |
| --- | --- |
| `apps/wear_os/app/src/test/java/com/fallguardian/FallReplay.kt` | Rejeu, décimation, max de créneau, métriques |
| `apps/wear_os/app/src/test/java/com/fallguardian/FallReplayTest.kt` | Corpus du dépôt et test de décimation |
| `apps/wear_os/app/src/test/resources/fall-replay/manifest.csv` | Identifiant, étiquette, fichier, résultat actuel |
| `apps/wear_os/app/src/test/resources/fall-replay/traces/*.csv` | `t_ms,ax_mps2,ay_mps2,az_mps2` |

Commande : `./gradlew :app:testDebugUnitTest --tests com.fallguardian.FallReplayTest` depuis `apps/wear_os`, ou `make -C apps/wear_os test` pour toute la suite JVM.

Un corpus externe, même manifeste à côté de ses CSV :

```text
./gradlew :app:testDebugUnitTest --tests com.fallguardian.FallReplayTest \
  -Dfall.replay.dir=/chemin/du/corpus
```

`app/build.gradle` transmet cette propriété à la JVM de test. Le test externe affiche les métriques et ne fait pas échouer le build : un jeu public ne doit pas être un secret de CI, ni un téléchargement caché.

### Définitions

Une trace est un fichier. L'automate est réinitialisé au début. Un épisode est une transition vers `processSample == true`, suivie du `reset()` et du silence de 5 s du service. Cela compte plusieurs alertes dans un long fichier ADL, au lieu de s'arrêter au premier vrai.

- Sensibilité = traces `fall` avec au moins un épisode / nombre de traces `fall`.
- Spécificité = traces `adl` avec zéro épisode / nombre de traces `adl`.
- Fausses alertes par jour = (somme des épisodes sur les traces `adl`) / (somme des durées ADL) × 86 400 s.

La durée d'une trace est le dernier horodatage moins le premier. Sur les clips de quelques secondes du dépôt, le taux par jour est un nombre énorme sans signification. Il devient le bon indicateur sur des ADL d'une heure ou plus, ou sur une journée reconstruite. La spécificité par clip et le taux par jour répondent à deux questions différentes ; les deux sont calculés.

Latence : horodatage du premier épisode moins horodatage du premier échantillon au-dessus du seuil d'impact. Sur `qualified_low_phase_25hz`, 2 320 ms. C'est le délai avant l'ouverture de la grâce, pas le délai avant l'aidant. L'aidant attend encore la grâce serveur de 30 s comptée depuis la réception API.

### Ce qu'il faut rejouer

**FallAllD, en premier.** Jeu ouvert, compte IEEE gratuit, pas d'adhésion requise. Poignet, taille et cou. Accéléromètre 238 Hz, ±8 g ; gyroscope 238 Hz, ±2 000 °/s ; magnétomètre 80 Hz ; baromètre 10 Hz. 15 sujets, chutes et ADL simulées, 26 420 fichiers. Papier : Saleh et al., doi:10.1109/JSEN.2020.3018335. Données : [IEEE DataPort 10.21227/bnya-mn34](https://ieee-dataport.org/open-access/fallalld-comprehensive-dataset-human-falls-and-activities-daily-living). Ne garder que le dispositif poignet. Convertir l'accélération en m/s² après avoir lu l'unité dans le script officiel du jeu (`FallAllD_Files_to_Matlab_Struct` ou l'équivalent Python) : ne pas deviner le facteur. Produire le CSV du harness. Étiqueter avec les identifiants d'activité du papier. Jouer deux fois à 40 ms : `FallReplay.decimate` et `FallReplay.bucketPeak`. Publier les deux lignes de métriques.

**Exports diagnostic Wear OS, en second.** Le journal local a déjà `ax_ms2,ay_ms2,az_ms2` et `sensor_elapsed_ms` (`FallDiagnosticSample.kt`). Une conversion en CSV du harness rejoue une vraie session dans l'automate d'aujourd'hui. Utile pour les faux positifs de marche, course, voiture, assise franche, montre posée. Ce n'est pas un jeu de chutes étiquetées tant qu'un protocole ne le dit pas.

**UP-Fall, en contrôle.** Martínez-Villaseñor et al., *Sensors*, 2019 (doi:10.3390/s19091988). Jeu public, IMU au poignet gauche parmi cinq capteurs, plus caméras. Adultes jeunes, chutes simulées. Second avis poignet, pas le jeu principal : la configuration capteur est moins explicite que FallAllD pour un rééchantillonnage à 25 Hz.

**À ne pas utiliser pour régler ce détecteur.**

- SisFall (Sucerquia, López, Vargas-Bonilla, *Sensors*, 2017, doi:10.3390/s17010198) : ceinture, 200 Hz, accéléromètre jusqu'à ±16 g, public, et c'est l'un des rares jeux avec des personnes âgées. Le papier montre aussi qu'un filtre à 5 Hz gardait l'essentiel **à la ceinture**, et que les chutes simulées par des jeunes sont plus violentes que celles des âgés. Utile pour un détecteur de ceinture. Le jouer tel quel sur l'automate poignet mesure un autre problème.
- MobiFall : téléphone dans la poche, accès sur demande. Mauvais placement.
- UMAFall : inclut un poignet, mais les capteurs portés y sont lents par rapport à FallAllD. Contrôle du comportement à bas débit, pas une référence de hauteur de pic.
- FARSEEING et les bases de chutes réelles : c'est la bonne question finale (Bagalà montre l'écart simulé / réel), et l'accès est restreint. Pas un téléchargement à mettre dans le dépôt.

Le corpus synthétique du dépôt reste le test de non-régression des mécanismes. Il ne remplace pas FallAllD. Quand un correctif change un `expect_detected`, le manifeste se met à jour dans le même commit, avec une ligne dans le message qui dit quel mécanisme a bougé.

Protocole minimal pour un changement de seuil ou de porte :

1. `FallReplayTest` vert sur le manifeste, ou manifeste mis à jour et justifié.
2. FallAllD poignet, décimation 40 ms et max de créneau, sensibilité globale, sensibilité des chutes lentes ou molles si le jeu les sépare, fausses alertes par heure d'ADL.
3. Aucune de ces deux lignes n'est une performance clinique. L'écrire dans le résultat.

## 5. Hors détection

Court. L'alerte elle-même est plus aboutie que le détecteur : grâce côté serveur, identifiant client idempotent, relais natif téléphone, annulation pendant la grâce.

**Fiabilité d'alerte.** Un push échoué est enregistré sur `PushAttempt` ; le handler ne replanifie pas cet envoi (`SendFallAlertPushMessageHandler.php` lignes 83-96). `messenger.yaml` n'a pas de `retry_strategy`. `OverdueAlertReconciler` remet en file les alertes dont l'échéance de grâce est passée ou dont le claim de dispatch est resté bloqué, pas les FCM déjà marqués en échec. La position arrivée après le push n'est pas renvoyée (section 1.6). Les échéances `delivery_receipt_deadline_at` et `acknowledgement_deadline_at` sont posées ; aucun handler lu ici n'escalade quand elles expirent.

**watchOS en arrière-plan.** Le relais iPhone existe. La montre n'appelle pas l'API elle-même. Si l'iPhone est injoignable, `transferUserInfo` met l'événement de côté ; la grâce de 30 s ne commence qu'à la réception serveur. Un événement livré tard part vers les aidants tard, ou immédiatement si la grâce est déjà comptée depuis `received_at` et que le traitement a du retard. À garder en tête quand on lira des délais réels.

**Vie privée.** Coordonnées en clair dans PostgreSQL et, si présentes, dans le data FCM, donc chez Google pour la remise. Jetons FCM aidants en clair (`CaregiverPushToken.php` ligne 26). Jetons d'appareil hachés en HMAC-SHA256 (`DeviceTokenHasher.php` lignes 14-16), avec un repli SHA-256 encore accepté le temps d'une rotation. Les traces accéléromètre restent sur la montre, 72 h, 64 Mio, export ADB (`FallDiagnosticStore.kt`). Pas de politique de rétention des alertes et des positions : le projet le marque non fait (`SYSTEM_OVERVIEW.md` ligne 544). Pour un produit grand public sur des données de chute et de position, c'est le sujet suivant, pas un détail.

**Architecture.** `packages/` ne contient pas le contrat. Les seuils voyagent par des clés `thresh_*` dupliquées dans Flutter, Kotlin et Swift. Les commentaires ont déjà divergé du ET réel. Un seul automate, appelé par les deux montres et par le harness, supprimerait cette classe de dérive. Le copier en Swift n'a pas de valeur tant que `start()` n'est pas appelé.

**Tests.** Behat couvre la création, l'idempotence, l'annulation et le push factice. Il ne couvre pas l'attache de position, l'annulation après la grâce, ni un FCM partiellement en échec de bout en bout. Les tests d'automate couvrent des paliers, désormais complétés par le rejeu CSV. Rien ne couvre une chute réelle.

## Sources

- Code Fall Guardian, `main` à `c4a12d7`, fichiers cités.
- Apple, « Use Fall Detection with Apple Watch », support 108896, consulté le 1er novembre 2026. https://support.apple.com/en-us/108896
- Apple, « Manage Fall Detection on Apple Watch ». https://support.apple.com/guide/watch/manage-fall-detection-apd34c409704/watchos
- Apple Newsroom, 12 septembre 2018, Apple Watch Series 4. https://www.apple.com/nz/newsroom/2018/09/redesigned-apple-watch-series-4-revolutionizes-communication-fitness-and-health/
- Apple Developer Documentation, `CMFallDetectionManager`. https://developer.apple.com/documentation/coremotion/cmfalldetectionmanager
- Kangas et al. Comparison of low-complexity fall detection algorithms for body attached accelerometers. *Gait & Posture*, 2008. doi:10.1016/j.gaitpost.2008.01.003
- Kangas. Development of accelerometry-based fall detection: from laboratory environment to real life. Université d'Oulu, 2011. https://oulurepo.oulu.fi/bitstream/handle/10024/35939/isbn978-951-42-9685-7.pdf
- Bagalà et al. Evaluation of Accelerometer-Based Fall Detection Algorithms on Real-World Falls. *PLoS ONE*, 2012. doi:10.1371/journal.pone.0037062
- Sucerquia, López, Vargas-Bonilla. SisFall: A Fall and Movement Dataset. *Sensors*, 2017. doi:10.3390/s17010198
- Saleh, Abbas, Le Bouquin Jeannès. FallAllD. *IEEE Sensors Journal*, 2021. doi:10.1109/JSEN.2020.3018335 — données doi:10.21227/bnya-mn34
- Martínez-Villaseñor et al. UP-Fall Detection Dataset. *Sensors*, 2019. doi:10.3390/s19091988
