import 'package:flutter/material.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static AppLocalizations forLocale(Locale locale) {
    return switch (locale.languageCode) {
      'fr' => AppLocalizationsFr(),
      _ => AppLocalizationsEn(),
    };
  }

  static const delegate = _AppLocalizationsDelegate();

  static const supportedLocales = [Locale('en'), Locale('fr')];

  // ── Generic ───────────────────────────────────────────────────────────────
  String get appTitle;

  // ── Home ──────────────────────────────────────────────────────────────────
  String get statusLinkedTitle;
  String get statusUnlinkedTitle;
  String get statusLinkedBody;
  String get statusUnlinkedBody;
  String get linkedSnackbar;
  String get linkButton;
  String get statusCardTitle;
  String get howItWorksTitle;
  String get statusCardBody;
  String get howItWorksBody;
  String get importantTitle;
  String get importantBody;
  String get homeFootnote;

  // ── Active Alert ──────────────────────────────────────────────────────────
  String get fallDetectedTitle;
  String detectedAt(String time);
  String get locationTitle;
  String get alertIdTitle;
  String get acknowledge;

  // ── Link ──────────────────────────────────────────────────────────────────
  String get linkScreenTitle;
  String get enterInviteCodeTitle;
  String get inviteCodeInstructions;
  String get codeFieldLabel;
  String get codeFieldValidation;
  String get codeNotFound;
  String inviteFailed(int code);
  String get connectionError;
  String get linkAsCaregiverButton;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations.forLocale(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
