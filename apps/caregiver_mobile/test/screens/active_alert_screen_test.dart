import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/active_alert_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('active alert screen shows actionable caregiver guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActiveAlertScreen(
          alertData: const {
            'alertId': 'alert-123',
            'fallTimestamp': '2026-06-16T19:50:03+00:00',
            'latitude': '48.8566',
            'longitude': '2.3522',
          },
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('FALL DETECTED'), findsOneWidget);
    expect(
      find.textContaining('Acknowledge when you have seen this alert'),
      findsOneWidget,
    );
    expect(find.text('Emergency actions'), findsOneWidget);
    expect(
      find.textContaining(
        'If there is no answer or the situation looks serious',
      ),
      findsOneWidget,
    );
    expect(find.text('Lat: 48.8566\nLng: 2.3522'), findsOneWidget);
  });

  testWidgets('active alert screen does not mention location when missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActiveAlertScreen(
          alertData: const {
            'alertId': 'alert-123',
            'fallTimestamp': '2026-06-16T19:50:03+00:00',
          },
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('use the location below'), findsNothing);
    expect(find.textContaining('no location was provided'), findsOneWidget);
    expect(find.text('Location'), findsNothing);
  });
}
