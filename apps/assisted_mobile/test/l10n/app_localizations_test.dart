import 'package:fall_guardian/l10n/app_localizations_en.dart';
import 'package:fall_guardian/l10n/app_localizations_fr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English alert copy explains cancellation and history status', () {
    final l10n = AppLocalizationsEn();

    expect(l10n.fallAlertBody, contains('Cancel if you are OK'));
    expect(l10n.fallAlertBody, contains('saved in history'));
    expect(l10n.statusAlertSent, 'Alert sent to caregivers');
    expect(l10n.statusCancelled, 'Cancelled by protected person');
    expect(
      l10n.statusCancellationPending,
      'Cancellation confirmation pending',
    );
  });

  test('French alert copy explains cancellation and history status', () {
    final l10n = AppLocalizationsFr();

    expect(l10n.fallAlertBody, contains('Annulez si vous allez bien'));
    expect(l10n.fallAlertBody, contains('historique'));
    expect(l10n.statusAlertSent, 'Alerte envoyée aux aidants');
    expect(l10n.statusCancelled, 'Annulée par la personne protégée');
    expect(
      l10n.statusCancellationPending,
      'Confirmation de l’annulation en attente',
    );
  });
}
