import 'package:caregiver_app/l10n/app_localizations_en.dart';
import 'package:caregiver_app/l10n/app_localizations_fr.dart';
import 'package:caregiver_app/utils/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 16, 12);

  test('formats elapsed time in English', () {
    final l10n = AppLocalizationsEn();
    String label(Duration ago) =>
        relativeTimeLabel(l10n, now.subtract(ago), now);

    expect(label(const Duration(seconds: 30)), 'just now');
    expect(label(const Duration(minutes: 5)), '5 min ago');
    expect(label(const Duration(hours: 2, minutes: 10)), '2 h ago');
    expect(label(const Duration(days: 1)), '1 day ago');
    expect(label(const Duration(days: 3)), '3 days ago');
    expect(label(const Duration(minutes: -10)), 'just now');
  });

  test('formats elapsed time in French', () {
    final l10n = AppLocalizationsFr();
    String label(Duration ago) =>
        relativeTimeLabel(l10n, now.subtract(ago), now);

    expect(label(Duration.zero), 'à l’instant');
    expect(label(const Duration(minutes: 7)), 'il y a 7 min');
    expect(label(const Duration(hours: 1)), 'il y a 1 h');
    expect(label(const Duration(days: 1)), 'il y a 1 jour');
    expect(label(const Duration(days: 2)), 'il y a 2 jours');
  });
}
