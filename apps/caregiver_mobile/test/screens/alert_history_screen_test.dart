import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/alert_history_screen.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('successful retry clears an earlier history load error', (
    tester,
  ) async {
    final backend = _RetryBackendService();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AlertHistoryScreen(backend: backend),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load history'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load history'), findsNothing);
    expect(find.text('Marie'), findsOneWidget);
    expect(find.text('1 alert'), findsOneWidget);
  });
}

class _RetryBackendService extends CaregiverBackendService {
  var _attempt = 0;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverAlerts() async {
    _attempt++;
    if (_attempt == 1) {
      throw CaregiverApiException('Backend unavailable');
    }

    return [
      {
        'id': 'alert-1',
        'protectedDeviceId': 'protected-device-1',
        'protectedDevicePlatform': 'ios',
        'protectedPersonName': 'Marie',
        'fallDetectedAt': '2026-07-24T17:00:00+00:00',
        'status': 'cancelled',
      },
    ];
  }
}
