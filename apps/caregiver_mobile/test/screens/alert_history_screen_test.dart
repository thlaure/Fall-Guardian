import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/alert_history_screen.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:material_ui/material_ui.dart';
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

  testWidgets('shows handling status per alert and keeps undated last', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AlertHistoryScreen(backend: _StatusBackendService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Handled by you'), findsOneWidget);
    expect(find.text('Waiting for you to respond'), findsNWidgets(2));
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(find.text('3 alerts'), findsOneWidget);
    final handledY = tester.getTopLeft(find.text('Handled by you')).dy;
    final waitingY = tester
        .getTopLeft(find.text('Waiting for you to respond').first)
        .dy;
    expect(handledY, lessThan(waitingY));
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

class _StatusBackendService extends CaregiverBackendService {
  @override
  Future<List<Map<String, dynamic>>> getCaregiverAlerts() async => [
    {
      'id': 'undated',
      'protectedDeviceId': 'device-1',
      'protectedDevicePlatform': 'ios',
      'fallDetectedAt': 'not a date',
      'status': 'sent',
      'acknowledged': false,
    },
    {
      'id': 'handled',
      'protectedDeviceId': 'device-1',
      'protectedDevicePlatform': 'ios',
      'fallDetectedAt': '2026-07-24T17:00:00+00:00',
      'status': 'sent',
      'acknowledged': true,
      'latitude': 48.85,
      'longitude': 2.35,
    },
    {
      'id': 'other-undated',
      'protectedDeviceId': 'device-1',
      'protectedDevicePlatform': 'ios',
      'fallDetectedAt': null,
      'status': 'sent',
      'acknowledged': false,
    },
  ];
}
