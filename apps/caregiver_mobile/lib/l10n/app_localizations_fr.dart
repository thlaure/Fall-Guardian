import 'app_localizations.dart';

class AppLocalizationsFr extends AppLocalizations {
  // ── Generic ───────────────────────────────────────────────────────────────
  @override
  String get appTitle => 'Fall Guardian Aidant';

  // ── Home ──────────────────────────────────────────────────────────────────
  @override
  String get statusLinkedTitle => 'Surveillance active';
  @override
  String get statusUnlinkedTitle => 'Non lié';
  @override
  String get statusLinkedBody =>
      'Vous recevrez des alertes si une chute est détectée sur l\'appareil d\'une personne protégée liée.';
  @override
  String get statusUnlinkedBody =>
      'Liez-vous à une personne protégée pour commencer à recevoir les alertes de chute.';
  @override
  String get linkedSnackbar =>
      'Lien établi ! Vous recevrez désormais les alertes de chute.';
  @override
  String get linkButton => 'Ajouter une personne protégée';
  @override
  String get relinkButton => 'Ajouter une autre personne protégée';
  @override
  String get protectedPersonsButton => 'Voir les personnes protégées';
  @override
  String get statusCardTitle => 'Statut';
  @override
  String get howItWorksTitle => 'Comment ça fonctionne';
  @override
  String get statusCardBody =>
      'Les notifications push sont actives. Gardez cette application installée.';
  @override
  String get howItWorksBody =>
      '1. Demandez à chaque personne protégée de générer un code dans son application Fall Guardian.\n'
      '2. Appuyez sur "Ajouter une personne protégée" ci-dessus et entrez le code.\n'
      '3. Vous recevrez des alertes push à chaque chute détectée.';
  @override
  String get importantTitle => 'Important';
  @override
  String get importantBody =>
      'Gardez les notifications activées pour cette application. Les alertes de chute sont '
      'envoyées comme messages silencieux — votre téléphone doit être allumé et connecté.';

  // ── Active Alert ──────────────────────────────────────────────────────────
  @override
  String get fallDetectedTitle => 'CHUTE DÉTECTÉE';
  @override
  String detectedAt(String time) => 'Détectée à $time';
  @override
  String get locationTitle => 'Position';
  @override
  String get alertIdTitle => 'ID alerte';
  @override
  String get acknowledge => 'Acquitter';
  @override
  String get activeAlertGuidanceWithLocation =>
      'Acquittez quand vous avez vu cette alerte. Si vous n’arrivez pas à joindre la personne protégée, utilisez la position ci-dessous et appelez les secours.';
  @override
  String get activeAlertGuidanceWithoutLocation =>
      'Acquittez quand vous avez vu cette alerte. Si vous n’arrivez pas à joindre la personne protégée, appelez les secours et indiquez qu’aucune position n’a été fournie.';
  @override
  String get activeAlertEmergencyTitle => 'Actions d’urgence';
  @override
  String get activeAlertEmergencyBody =>
      'Appelez d’abord la personne protégée si possible. Sans réponse ou si la situation semble grave, appelez les secours.';

  // ── Link ──────────────────────────────────────────────────────────────────
  @override
  String get linkScreenTitle => 'Ajouter une personne protégée';
  @override
  String get enterInviteCodeTitle => 'Entrer le code d\'invitation';
  @override
  String get inviteCodeInstructions =>
      'Demandez à la personne protégée de générer un code dans son application Fall Guardian. Vous pouvez répéter cette opération pour plusieurs personnes.';
  @override
  String get protectedPersonNameFieldLabel => 'Nom de la personne protégée';
  @override
  String get protectedPersonNameValidation =>
      'Entrez un nom d’au moins 2 caractères';
  @override
  String get caregiverNameFieldLabel => 'Votre nom d’aidant';
  @override
  String get caregiverNameValidation =>
      'Entrez votre nom avec au moins 2 caractères';
  @override
  String get codeFieldLabel => 'Code d\'invitation à 32 caractères';
  @override
  String get codeFieldValidation => 'Entrez le code complet à 32 caractères';
  @override
  String get codeNotFound =>
      'Code introuvable ou expiré. Demandez un nouveau code.';
  @override
  String inviteFailed(int code) => 'Échec de l\'invitation ($code).';
  @override
  String get connectionError =>
      'Erreur de connexion. Vérifiez le réseau et que le backend est joignable.';
  @override
  String get linkAsCaregiverButton => 'Ajouter en tant qu\'aidant';

  // ── Protected Persons ─────────────────────────────────────────────────────
  @override
  String get protectedPersonsTitle => 'Personnes protégées';
  @override
  String get protectedPersonsLoadFailed =>
      'Impossible de charger les personnes protégées';
  @override
  String get protectedPersonsEmptyTitle => 'Aucune personne protégée';
  @override
  String get protectedPersonsEmptyBody =>
      'Demandez à une personne protégée de générer un code d’invitation, puis ajoutez-la ici.';
  @override
  String get protectedPersonDeviceIdTitle => 'ID appareil';
  @override
  String protectedPersonsCount(int count) =>
      count == 1 ? '1 personne protégée' : '$count personnes protégées';

  // ── History ───────────────────────────────────────────────────────────────
  @override
  String get historyTitle => 'Historique des chutes';
  @override
  String get historyLoadFailed => 'Impossible de charger l’historique';
  @override
  String get retry => 'Réessayer';
  @override
  String get historyEmpty => 'Aucune alerte de chute';
  @override
  String protectedPersonLabel(int number) => 'Personne protégée $number';
  @override
  String protectedPersonSubtitle(String platform, String shortId) =>
      'Appareil ${platform.toUpperCase()} $shortId';
  @override
  String alertCountLabel(int count) =>
      count == 1 ? '1 alerte' : '$count alertes';
  @override
  String get statusStoppedByProtectedPerson =>
      'Annulée par la personne protégée';
  @override
  String get statusAcknowledged => 'Acquittée par un aidant';
  @override
  String get statusUnacknowledged => 'À acquitter par un aidant';
  @override
  String get unknownDate => 'Date inconnue';
}
