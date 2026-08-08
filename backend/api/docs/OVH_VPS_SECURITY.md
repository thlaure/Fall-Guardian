# Sécurité MVP — VPS OVH

Ce guide couvre le minimum opérationnel pour déployer l'API familiale. Il ne
remplace pas la validation produit, médicale ou réglementaire.

## Avant premier déploiement

1. Configurer `api.votre-domaine.fr` vers l'adresse IPv4/IPv6 du VPS.
2. Créer un fichier d'environnement hors du dépôt à partir de
   `.env.prod.example`. Générer des valeurs distinctes et aléatoires pour
   `APP_SECRET`, `DEVICE_TOKEN_HASH_SECRET` et `POSTGRES_PASSWORD`.
3. Définir `SERVER_NAME=https://api.votre-domaine.fr` et `PUSH_PROVIDER=fcm`.
   Ne jamais utiliser `fake` en production.
4. Laisser `CORS_ALLOW_ORIGIN=^$` tant qu'aucun client web n'existe. Les
   applications iOS et Android natives n'ont pas besoin de CORS.
5. Configurer pare-feu OVH et pare-feu système : ouvrir seulement 80/443 et
   SSH. Restreindre SSH à l'adresse IP d'administration quand possible.
   PostgreSQL et Redis restent accessibles uniquement dans le réseau Docker.

## À chaque déploiement

1. Vérifier la sauvegarde PostgreSQL la plus récente.
2. Déployer une image immuable validée par CI.
3. Exécuter la migration ; arrêter le déploiement si elle échoue.
4. Vérifier `https://api.votre-domaine.fr/health`.
5. Vérifier worker Messenger, reconciler et une livraison FCM réelle.

## Exploitation

- Sauvegarder PostgreSQL au moins quotidiennement, chiffrer la sauvegarde et
  conserver une copie hors VPS.
- Tester une restauration avant ouverture publique, puis mensuellement.
- Surveiller disponibilité `/health`, erreurs 5xx, pics 401/429, échecs FCM et
  messages Messenger en échec.
- En cas de perte de téléphone ou montre : révoquer son appareil depuis un
  appareil de la même personne protégée avec `POST /api/v1/devices/{deviceId}/revoke`.
  Le token révoqué est refusé dès la requête suivante.
- Ne jamais mettre secrets, sauvegardes ou logs contenant données de santé dans Git.
