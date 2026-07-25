# Enrôlement des montres — contrat et plan d'intégration

> État de référence au 25 juillet 2026.
>
> Le support serveur est disponible sur `main` depuis la PR
> [#79](https://github.com/thlaure/Fall-Guardian/pull/79). Les applications
> téléphone, watchOS et Wear OS ne consomment pas encore ce parcours.

## 1. Objectif

Chaque montre doit devenir un appareil authentifié propre, rattaché à la même
personne protégée que le téléphone. La montre ne reçoit jamais le jeton durable
du téléphone.

Le parcours doit fonctionner sans saisie manuelle d'un secret long :

1. le téléphone authentifié demande un enrôlement pour sa plateforme ;
2. l'API retourne un jeton éphémère valable cinq minutes ;
3. le téléphone transmet ce jeton à la montre associée ;
4. la montre échange le jeton contre ses propres identifiants ;
5. elle stocke ces identifiants de manière sécurisée ;
6. elle peut ensuite envoyer directement incidents et annulations à l'API.

## 2. Contrat API disponible

### 2.1 Créer un enrôlement depuis le téléphone

```http
POST /api/v1/companion-enrollments
Authorization: Bearer <deviceToken du téléphone>
Content-Type: application/json

{
  "platform": "watchos"
}
```

`platform` accepte uniquement `watchos` ou `wearos`.

Réponse `201` :

```json
{
  "enrollmentToken": "<jeton de 64 caractères>",
  "expiresAt": "2026-07-25T10:05:00+00:00"
}
```

Seul un appareil rattaché à une personne protégée peut créer cet enrôlement.
Un appareil aidant reçoit une erreur `422`. La création est limitée en débit
par appareil protégé.

### 2.2 Consommer l'enrôlement depuis la montre

Cet appel est public car la montre ne possède pas encore d'identifiants.

```http
POST /api/v1/companion-enrollments/claim
Content-Type: application/json

{
  "enrollmentToken": "<jeton reçu du téléphone>",
  "platform": "watchos",
  "appVersion": "1.0.0"
}
```

Réponse `201` :

```json
{
  "deviceId": "<identifiant propre à la montre>",
  "deviceToken": "<secret propre à la montre>"
}
```

Un jeton expiré, déjà utilisé ou présenté pour la mauvaise plateforme reçoit
une erreur `404`. Une tentative avec mauvaise plateforme ne consomme pas le
jeton. La consommation est atomique : deux demandes simultanées ne peuvent pas
créer deux appareils.

### 2.3 Garanties serveur

- durée de vie : cinq minutes ;
- usage unique ;
- plateforme imposée ;
- stockage du jeton d'enrôlement uniquement sous forme de hash HMAC ;
- rattachement automatique de la montre à la personne protégée ;
- identifiants durables distincts pour téléphone et montre ;
- déduplication des alertes par personne protégée + `clientAlertId`.

## 3. Responsabilités des clients

### Téléphone de la personne aidée

- proposer « Connecter la montre » seulement après enregistrement du téléphone ;
- choisir la plateforme correcte sans laisser l'utilisateur la modifier ;
- demander un nouvel enrôlement à chaque tentative ;
- transmettre `enrollmentToken` et `expiresAt` via le canal local officiel ;
- ne jamais persister le jeton éphémère au-delà du parcours ;
- afficher attente, succès, expiration et nouvelle tentative ;
- ne jamais transmettre son propre `deviceToken`.

### Montre

- accepter uniquement un message d'enrôlement provenant de l'app associée ;
- vérifier plateforme et expiration avant l'appel réseau ;
- appeler `/claim` immédiatement ;
- stocker `deviceId` et `deviceToken` dans le stockage sécurisé natif ;
- confirmer le succès au téléphone sans lui renvoyer `deviceToken` ;
- conserver les identifiants après redémarrage ;
- remplacer proprement des identifiants invalides lors d'un nouvel enrôlement ;
- ne jamais journaliser jeton d'enrôlement ou jeton d'appareil.

### Stockage recommandé

| Plateforme | Secret durable | Données non sensibles |
| --- | --- | --- |
| watchOS | Keychain de l'extension | `deviceId`, version du schéma, date d'enrôlement |
| Wear OS | Android Keystore + stockage chiffré | `deviceId`, version du schéma, date d'enrôlement |
| iOS | Keychain existant | aucun jeton d'enrôlement durable |
| Android | Keystore/stockage sécurisé existant | aucun jeton d'enrôlement durable |

## 4. Transport local de l'enrôlement

### watchOS

Le téléphone crée le jeton, puis l'envoie avec `WCSession.sendMessage` si la
montre est joignable. `transferUserInfo` sert de repli avant expiration.

Message proposé :

```json
{
  "type": "companionEnrollment",
  "schemaVersion": 1,
  "platform": "watchos",
  "enrollmentToken": "<jeton>",
  "expiresAt": "2026-07-25T10:05:00+00:00"
}
```

L'URL de production doit venir de la configuration signée de l'application,
pas du message reçu. Une URL de développement peut rester une option de build
explicite.

La montre répond uniquement avec :

```json
{
  "type": "companionEnrollmentResult",
  "schemaVersion": 1,
  "status": "enrolled"
}
```

### Wear OS

Le téléphone utilise `MessageClient` pour le chemin immédiat et `DataClient`
comme repli durable court. Le message reprend le même schéma logique. L'élément
Data Layer doit être supprimé après succès ou expiration.

## 5. UX minimale

État téléphone :

```text
Montre non connectée
→ Connexion en cours
→ Montre connectée
```

Erreurs récupérables :

- montre hors de portée : garder l'écran ouvert et permettre « Réessayer » ;
- jeton expiré : créer automatiquement un nouveau jeton ;
- Internet absent sur montre : conserver l'état « Connexion en attente », puis
  créer un nouveau jeton lorsque la montre retrouve un chemin réseau ;
- identifiants déjà présents : afficher « Montre connectée » et proposer une
  reconnexion explicite ;
- changement de téléphone : permettre un nouvel enrôlement sans dupliquer les
  incidents grâce à l'identité stable.

Ne pas afficher le jeton brut à l'utilisateur. Aucun QR code n'est nécessaire
tant que téléphone et montre utilisent leur canal d'association natif.

## 6. Découpage recommandé des prochaines PR

### PR A — orchestration téléphone

- ajouter client API de création d'enrôlement dans l'app personne aidée ;
- ajouter action et états « Connecter la montre » ;
- transmettre le message versionné vers watchOS et Wear OS ;
- ajouter tests Flutter et tests des ponts natifs ;
- ne pas inclure encore l'envoi direct des alertes.

### PR B — consommation watchOS

- recevoir le message d'enrôlement ;
- appeler `/claim` avec `URLSession` ;
- stocker les identifiants dans Keychain ;
- confirmer le succès à l'iPhone ;
- couvrir succès, expiration, mauvais format, redémarrage et secret absent.

### PR C — consommation Wear OS

- recevoir le message via Data Layer ;
- appeler `/claim` avec client HTTPS natif ;
- stocker le secret via Android Keystore ;
- confirmer le succès au téléphone ;
- couvrir les mêmes cas que watchOS.

### PR D — transport direct watchOS

- file persistante d'incidents et d'annulations ;
- HTTPS authentifié avec identifiants montre ;
- direct et relais lancés avec le même `clientAlertId` ;
- reprise après perte réseau ou redémarrage.

### PR E — transport direct Wear OS et relais Android natif

- file persistante côté montre ;
- HTTPS direct ;
- réception native Android indépendante de Flutter ;
- reprise après processus tué ou redémarrage.

## 7. Critères d'acceptation de l'enrôlement

| Scénario | Résultat attendu |
| --- | --- |
| Téléphone protégé + montre associée | Montre reçoit ses propres identifiants |
| Aidant tente un enrôlement | Refus `422` |
| Jeton utilisé deux fois | Première consommation réussie, seconde refusée |
| Jeton expiré | Nouveau jeton créé sans intervention technique |
| Plateforme incorrecte | Refus sans consommer le jeton |
| Deux claims simultanés | Une seule montre créée |
| Téléphone ou montre redémarre après succès | État connecté conservé |
| Secret absent ou corrompu | Reconnexion proposée, aucun faux succès |
| Journaux applicatifs inspectés | Aucun secret présent |
| Montre réenrôlée | Nouvelle identité utilisable, incidents toujours dédupliqués par personne |

## 8. Hors périmètre de l'enrôlement

L'enrôlement ne garantit pas encore :

- l'envoi direct d'une chute depuis la montre ;
- le relais natif quand Flutter ne tourne pas ;
- la reprise hors connexion ;
- la révocation d'une montre perdue ;
- l'affichage serveur de la liste des appareils compagnons ;
- la rotation automatique du jeton durable.

Ces points restent des incréments séparés. La révocation devra être traitée
avant une diffusion commerciale.
