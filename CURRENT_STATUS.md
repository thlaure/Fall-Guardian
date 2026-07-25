# Fall Guardian — état courant et passation

> État fonctionnel au 25 juillet 2026.
>
> Lire ce fichier en premier lors d'une reprise. La documentation d'architecture
> détaillée reste dans `docs/SYSTEM_OVERVIEW.md` et le contrat des montres dans
> `docs/COMPANION_ENROLLMENT.md`.

## 1. Point de départ

- Branche de référence : `main`.
- Dernière base fonctionnelle avant cette passation :
  `9397d29 feat(assisted): start secure watch enrollment (#81)`.
- PR #73 à #81 fusionnées après CI.
- Arbre de travail attendu : propre et synchronisé avec `origin/main`.

Toujours confirmer avant de commencer :

```sh
git status --short --branch
git log -5 --oneline
make status
```

## 2. Ce qui fonctionne

### Backend

- identité stable d'une personne protégée ;
- plusieurs appareils rattachés à la même personne ;
- déduplication par personne protégée + `clientAlertId` ;
- contrat d'incident versionné avec `revision`, `detectionSource` et
  `resolution` ;
- échéance serveur `cancelDeadlineAt` ;
- enrôlement `watchos` ou `wearos` valable cinq minutes, à usage unique,
  plateforme imposée et jeton stocké uniquement sous forme de hash HMAC ;
- notifications aidants, reçus, acquittements et historique.

### Application personne aidée

- enregistrement du téléphone et stockage sécurisé de ses identifiants ;
- enregistrement immédiat d'un incident, sans attendre la fin du compte à
  rebours ;
- annulation, ajout différé de la position et historique local ;
- réception des événements watchOS/Wear OS ;
- action « Connecter la montre » dans les paramètres ;
- création de l'enrôlement et transmission versionnée vers le pont natif ;
- états attente, erreur, expiration et réessai ;
- aucun jeton d'enrôlement persisté ou journalisé ;
- Android exige exactement une montre connectée avant d'envoyer le secret.

### Montres

- watchOS : détection système Apple, repli accéléromètre lorsque l'app est
  ouverte, compte à rebours, annulation et relais WatchConnectivity ;
- Wear OS : service de détection au premier plan, compte à rebours, annulation
  et relais Data Layer vers Android ;
- aucune montre ne consomme encore l'enrôlement ;
- aucune montre n'envoie encore directement un incident à l'API.

### Application aidant

- association avec plusieurs personnes ;
- réception push, écran d'alerte et historique ;
- nouvelle tentative du chargement d'historique après erreur ;
- reçus et acquittements.

## 3. Prochaine tâche exacte — PR B watchOS

Objectif : terminer l'enrôlement côté Apple Watch, sans ajouter encore l'envoi
direct des chutes.

### Comportement attendu

1. recevoir le message `companionEnrollment` envoyé par l'iPhone ;
2. vérifier `schemaVersion`, `platform`, jeton et expiration ;
3. appeler immédiatement
   `POST /api/v1/companion-enrollments/claim` avec `URLSession` ;
4. récupérer `deviceId` et `deviceToken` ;
5. stocker `deviceToken` dans Keychain et les métadonnées non sensibles
   séparément ;
6. confirmer à l'iPhone uniquement le statut `enrolled`, jamais le secret ;
7. conserver l'état après redémarrage ;
8. proposer un nouvel enrôlement si le secret est absent, corrompu ou refusé.

### Fichiers principaux

- `apps/watchos/FallGuardian/FallGuardian Watch App/WatchSessionManager.swift` :
  réception WatchConnectivity et confirmation ;
- nouveau service watchOS dédié au client `/claim` ;
- nouveau stockage Keychain dédié aux identifiants compagnon ;
- `apps/watchos/FallGuardianTests/` : contrat, expiration, erreurs et
  persistance ;
- projet Xcode watchOS et projet iOS embarquant la montre si de nouveaux
  fichiers Swift doivent être référencés explicitement ;
- `docs/COMPANION_ENROLLMENT.md` et `docs/SYSTEM_OVERVIEW.md`.

Le message entrant est déjà produit par le téléphone :

```json
{
  "type": "companionEnrollment",
  "schemaVersion": 1,
  "platform": "watchos",
  "enrollmentToken": "<64 caractères>",
  "expiresAt": "<date ISO-8601>"
}
```

L'URL de l'API doit venir d'une configuration de build explicite. Ne jamais
mettre une URL de production ou un secret en dur. Ne pas accepter une URL
arbitraire depuis le message WatchConnectivity.

### Critères de fin

- succès, expiration, réponse mal formée et refus serveur testés ;
- double livraison du même message sans double identité ;
- identifiants disponibles après redémarrage de l'extension ;
- aucun token visible dans les logs ;
- confirmation iPhone ne contient aucun token ;
- `make -C apps/watchos check` vert ;
- build de l'app iOS avec la montre embarquée vert ;
- documentation mise à jour.

## 4. Suite après PR B

Ordre recommandé :

1. PR C — consommation Wear OS + Android Keystore ;
2. PR D — file persistante et HTTPS direct watchOS ;
3. PR E — HTTPS direct Wear OS + relais Android natif indépendant de Flutter ;
4. UX de sécurité : appui long « Je vais bien », états réseau et prise en
   charge aidant ;
5. escalade, supervision, confidentialité et préparation commerciale.

Ne pas fusionner PR B avec l'envoi direct des chutes. Garder chaque incrément
testable et réversible.

## 5. Validations déjà réalisées

- backend : tests unitaires, intégration, Behat, qualité et sécurité ;
- app aidée : 151 tests, analyse statique et couverture supérieure ou égale à
  90 % lors de la PR #81 ;
- APK Android aidé compilé ;
- app iOS simulateur compilée avec compagnon Watch embarqué ;
- écran « Connexion de la montre » inspecté sur simulateur ;
- builds et tests déterministes watchOS/Wear OS existants verts en CI.

Ces validations ne prouvent pas le fonctionnement physique complet.

## 6. Tests physiques encore obligatoires

Aucun résultat physique complet n'est consigné à ce jour. Tester et enregistrer
date, versions OS, appareils, réseau et résultat pour chaque cas :

- Apple Watch réelle + iPhone verrouillé dans une poche ;
- montre sans Wi-Fi, iPhone à portée avec 4G/5G ;
- Apple Watch cellulaire sans iPhone ;
- Android verrouillé avec processus Flutter supprimé ;
- perte et retour réseau pendant le délai ;
- redémarrage téléphone et montre ;
- chute puis annulation presque simultanée ;
- direct montre et relais téléphone simultanés ;
- plusieurs aidants et plusieurs appareils.

## 7. Blocages et dépendances externes

### Apple

- équipe : Thomas Laure, Team ID `PTXCAH5P4R` ;
- app iOS : `com.fallguardian.app` ;
- app Watch : `com.fallguardian.app.watchkitapp` ;
- demande de capacité Fall Detection envoyée à Apple ;
- état connu : approbation en attente ;
- conséquence : validation physique de `CMFallDetectionManager` bloquée ou
  incomplète tant que la capacité n'est pas accordée.

Après approbation, régénérer ou actualiser les profils de provisioning avant
installation physique. Ne pas ajouter certificats ou profils au dépôt.

### Accès à transmettre hors Git

Le repreneur aura besoin, selon son rôle :

- accès au compte Apple Developer et à Xcode signing ;
- accès Firebase/FCM ;
- secrets et variables de l'environnement backend ;
- accès au dépôt GitHub et aux Actions ;
- iPhone, Apple Watch, Android et montre Wear OS de test.

Les secrets doivent être transmis par un gestionnaire de secrets, jamais dans
ce fichier, une issue ou une PR.

## 8. Lancement local

Depuis la racine :

```sh
make help
make status
make quality
```

Backend :

```sh
make -C backend/api up
make -C backend/api install
make -C backend/api test
make -C backend/api test-behat
```

App personne aidée :

```sh
make -C apps/assisted_mobile quality
make -C apps/assisted_mobile build-android
make -C apps/assisted_mobile build-ios
```

Montres :

```sh
make -C apps/watchos check
make -C apps/wear_os check
```

Pour appareils physiques et changement de réseau, suivre les README de chaque
projet. `BACKEND_BASE_URL` doit être fourni au build ; ne pas supposer que
`localhost` désigne le Mac depuis un appareil.

## 9. Limites produit critiques

- Fall Guardian n'appelle pas automatiquement les services d'urgence ;
- la fonction principale actuelle avertit les aidants liés via notification ;
- ancien code et anciens libellés Android liés au SMS existent encore et
  doivent être supprimés ou clarifiés avant commercialisation ;
- aucun transport ne peut fonctionner sans chemin réseau sur montre ou
  téléphone ;
- le relais Android processus tué n'est pas encore garanti ;
- révocation d'une montre perdue et rotation des jetons non implémentées ;
- escalade sans prise en charge aidant incomplète ;
- conservation, suppression et politique de faux positifs à définir ;
- validation médicale, urgence, confidentialité et promesse commerciale à
  réaliser avant diffusion.

## 10. Carte documentaire

- `CURRENT_STATUS.md` : état opérationnel et prochaine tâche ;
- `docs/SYSTEM_OVERVIEW.md` : fonctionnalités, architecture, limites et roadmap ;
- `docs/COMPANION_ENROLLMENT.md` : contrat et découpage PR A à E ;
- `README.md` : structure du monorepo et commandes communes ;
- README de chaque projet : installation, build et tests spécifiques ;
- `CLAUDE.md` racine et locaux : règles de contribution.

Mettre à jour ce fichier après chaque incrément majeur ou changement de blocage.
