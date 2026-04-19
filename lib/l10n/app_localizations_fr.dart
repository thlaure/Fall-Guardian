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
      'Vous recevrez des alertes si une chute est détectée sur l\'appareil de la personne protégée.';
  @override
  String get statusUnlinkedBody =>
      'Liez-vous à une personne protégée pour commencer à recevoir les alertes de chute.';
  @override
  String get linkedSnackbar =>
      'Lien établi ! Vous recevrez désormais les alertes de chute.';
  @override
  String get linkButton => 'Se lier à une personne protégée';
  @override
  String get statusCardTitle => 'Statut';
  @override
  String get howItWorksTitle => 'Comment ça fonctionne';
  @override
  String get statusCardBody =>
      'Les notifications push sont actives. Gardez cette application installée.';
  @override
  String get howItWorksBody =>
      '1. Demandez à la personne protégée de générer un code dans son application Fall Guardian.\n'
      '2. Appuyez sur "Se lier" ci-dessus et entrez le code.\n'
      '3. Vous recevrez des alertes push à chaque chute détectée.';
  @override
  String get importantTitle => 'Important';
  @override
  String get importantBody =>
      'Gardez les notifications activées pour cette application. Les alertes de chute sont '
      'envoyées comme messages silencieux — votre téléphone doit être allumé et connecté.';
  @override
  String get homeFootnote =>
      'Des applications séparées rendent les flux aidé/aidant plus clairs, plus sûrs et plus faciles à maintenir.';

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

  // ── Link ──────────────────────────────────────────────────────────────────
  @override
  String get linkScreenTitle => 'Se lier à une personne protégée';
  @override
  String get enterInviteCodeTitle => 'Entrer le code d\'invitation';
  @override
  String get inviteCodeInstructions =>
      'Demandez à la personne protégée de générer un code dans son application Fall Guardian.';
  @override
  String get codeFieldLabel => 'Code à 8 caractères';
  @override
  String get codeFieldValidation => 'Entrez le code complet à 8 caractères';
  @override
  String get codeNotFound =>
      'Code introuvable ou expiré. Demandez un nouveau code.';
  @override
  String inviteFailed(int code) => 'Échec de l\'invitation ($code).';
  @override
  String get connectionError =>
      'Erreur de connexion. Vérifiez le backend.';
  @override
  String get linkAsCaregiverButton => 'Se lier en tant qu\'aidant';
}
