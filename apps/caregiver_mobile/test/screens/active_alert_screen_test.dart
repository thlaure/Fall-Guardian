import 'dart:async';

import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/active_alert_screen.dart';
import 'package:caregiver_app/services/alert_actions.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _alertWithLocation = {
  'type': 'fall_alert',
  'alertId': 'alert-123',
  'fallTimestamp': '2026-06-16T19:50:03+00:00',
  'latitude': '48.8566',
  'longitude': '2.3522',
};

class _FakeBackend extends CaregiverBackendService {
  _FakeBackend({this.error});

  final Object? error;
  final List<String> acknowledged = [];
  Completer<void>? gate;

  @override
  Future<void> acknowledgeFallAlert(String alertId) async {
    acknowledged.add(alertId);
    await gate?.future;
    if (error != null) throw error!;
  }
}

class _FakeActions implements AlertActions {
  _FakeActions({this.succeeds = true});

  final bool succeeds;
  final List<String> calls = [];
  final List<(double, double)> maps = [];

  @override
  Future<bool> call(String phoneNumber) async {
    calls.add(phoneNumber);
    return succeeds;
  }

  @override
  Future<bool> openMap({
    required double latitude,
    required double longitude,
  }) async {
    maps.add((latitude, longitude));
    return succeeds;
  }
}

void main() {
  late _FakeBackend backend;
  late _FakeActions actions;
  late int dismissals;

  setUp(() {
    backend = _FakeBackend();
    actions = _FakeActions();
    dismissals = 0;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Map<String, dynamic> data = _alertWithLocation,
    ValueNotifier<Map<String, dynamic>>? live,
    Locale locale = const Locale('en'),
    String? deviceRegion = 'FR',
    int waitingCount = 0,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: theme,
        localizationsDelegates: [
          AppLocalizations.delegate,
          // Material, Cupertino and Widgets delegates (material_ui package).
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActiveAlertScreen(
          alertData: data,
          liveAlert: live,
          backend: backend,
          actions: actions,
          clock: () => DateTime.utc(2026, 6, 16, 19, 55, 3),
          deviceRegion: deviceRegion,
          waitingCount: waitingCount,
          onDismiss: () => dismissals++,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the protected person name, time and relative time', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      data: {..._alertWithLocation, 'protectedPersonName': 'Marie'},
    );

    expect(find.text('FALL DETECTED'), findsOneWidget);
    expect(find.text('Marie may have fallen'), findsOneWidget);
    expect(
      find.textContaining(RegExp('Detected on .*Jun 16.* at ')),
      findsOneWidget,
    );
    expect(find.textContaining('5 min ago'), findsOneWidget);
    expect(find.textContaining('I\'m handling it'), findsWidgets);
    expect(find.text('Emergency actions'), findsOneWidget);
  });

  testWidgets('falls back to a localized contact name when absent', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Your contact may have fallen'), findsOneWidget);
  });

  testWidgets('keeps technical ids and coordinates in collapsed details', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.textContaining('Lat:'), findsNothing);
    expect(find.textContaining('alert-123'), findsNothing);
    expect(find.text('Technical details'), findsOneWidget);

    await tester.ensureVisible(find.text('Technical details'));
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();

    expect(find.text('Alert ID: alert-123'), findsOneWidget);
    expect(find.text('Coordinates: 48.85660, 2.35220'), findsOneWidget);
  });

  testWidgets('opens maps for the fall location', (tester) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Open in Maps'));
    await tester.tap(find.text('Open in Maps'));
    await tester.pump();

    expect(actions.maps, [(48.8566, 2.3522)]);
  });

  testWidgets('reports when no maps app can open the location', (tester) async {
    actions = _FakeActions(succeeds: false);
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Open in Maps'));
    await tester.tap(find.text('Open in Maps'));
    await tester.pump();

    expect(find.text('No maps app could open this location.'), findsOneWidget);
  });

  testWidgets('hides maps when no location was provided', (tester) async {
    await pumpScreen(
      tester,
      data: const {
        'alertId': 'alert-123',
        'fallTimestamp': '2026-06-16T19:50:03+00:00',
      },
    );

    expect(find.text('Open in Maps'), findsNothing);
    expect(find.textContaining('no location was provided'), findsOneWidget);
  });

  testWidgets('calls the regional emergency number (112 in France)', (
    tester,
  ) async {
    await pumpScreen(tester);

    final button = find.text('Call emergency services (112)');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(actions.calls, ['112']);
  });

  testWidgets('uses 911 for US phones and reports dialer failures', (
    tester,
  ) async {
    actions = _FakeActions(succeeds: false);
    await pumpScreen(tester, deviceRegion: 'US');

    final button = find.text('Call emergency services (911)');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(actions.calls, ['911']);
    expect(find.text('Could not open the phone dialer.'), findsOneWidget);
  });

  testWidgets('"I\'m handling it" acknowledges then dismisses', (tester) async {
    backend.gate = Completer<void>();
    await pumpScreen(tester);

    await tester.tap(find.text('I\'m handling it'));
    await tester.pump();

    expect(backend.acknowledged, ['alert-123']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(dismissals, 0);

    backend.gate!.complete();
    await tester.pump();

    expect(dismissals, 1);
  });

  testWidgets('acknowledgement failure keeps the alert open', (tester) async {
    backend = _FakeBackend(error: CaregiverApiException('offline'));
    await pumpScreen(tester);

    await tester.tap(find.text('I\'m handling it'));
    await tester.pump();
    await tester.pump();

    expect(dismissals, 0);
    expect(find.textContaining('Connection error'), findsOneWidget);
    expect(find.text('I\'m handling it'), findsOneWidget);
  });

  testWidgets('an alert without id cannot be acknowledged', (tester) async {
    await pumpScreen(tester, data: const {'fallTimestamp': 'garbage'});

    expect(find.textContaining('Detected at garbage'), findsOneWidget);
    await tester.tap(find.text('I\'m handling it'));
    await tester.pump();

    expect(backend.acknowledged, isEmpty);
    expect(dismissals, 0);
  });

  testWidgets('shows when another caregiver already handles the alert', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      data: {
        ..._alertWithLocation,
        'acknowledgedByMe': 'false',
        'acknowledgementCount': '1',
        'acknowledgedAt': '2026-06-16T19:52:00+00:00',
      },
    );

    expect(
      find.textContaining('Another caregiver is handling this since'),
      findsOneWidget,
    );

    // The caregiver can still take over, or close the screen.
    await tester.tap(find.text('Close'));
    expect(dismissals, 1);

    await tester.tap(find.text('I\'m handling it'));
    await tester.pump();
    expect(backend.acknowledged, ['alert-123']);
  });

  testWidgets('updates live when polling reports a new handler', (
    tester,
  ) async {
    final live = ValueNotifier<Map<String, dynamic>>(_alertWithLocation);
    await pumpScreen(tester, live: live);

    expect(find.textContaining('Another caregiver'), findsNothing);
    expect(find.text('Close'), findsNothing);

    live.value = {..._alertWithLocation, 'acknowledgementCount': '2'};
    await tester.pump();

    expect(find.text('Another caregiver is handling this'), findsOneWidget);

    live.value = {..._alertWithLocation, 'acknowledgedByMe': 'true'};
    await tester.pump();

    expect(find.text('You are handling this'), findsOneWidget);
  });

  testWidgets('shows the reminder banner and queued alerts', (tester) async {
    await pumpScreen(
      tester,
      data: {..._alertWithLocation, 'reminder': '1'},
      waitingCount: 2,
    );

    expect(find.text('Reminder — no one has responded yet'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('2 more alerts waiting'), 100);
    expect(find.text('2 more alerts waiting'), findsOneWidget);
  });

  testWidgets('is fully localized in French', (tester) async {
    await pumpScreen(
      tester,
      locale: const Locale('fr'),
      data: {
        ..._alertWithLocation,
        'protectedPersonName': 'Marie',
        'reminder': '1',
      },
    );

    expect(find.text('CHUTE DÉTECTÉE'), findsOneWidget);
    expect(find.text('Marie a peut-être chuté'), findsOneWidget);
    expect(find.textContaining('il y a 5 min'), findsOneWidget);
    expect(find.text('Je m’en occupe'), findsOneWidget);
    expect(find.text('Rappel — personne n’a encore répondu'), findsOneWidget);
    expect(find.text('Appeler les secours (112)'), findsOneWidget);
    expect(find.text('Ouvrir dans Plans'), findsOneWidget);
  });

  testWidgets('exposes semantics for the alert and its actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
      tester,
      data: {..._alertWithLocation, 'protectedPersonName': 'Marie'},
    );

    expect(find.bySemanticsLabel('Fall alert for Marie'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Marie may have fallen')),
      matchesSemantics(label: 'Marie may have fallen', isHeader: true),
    );
    expect(
      find.bySemanticsLabel(RegExp('Call emergency services')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r"^I'm handling it$")), findsOneWidget);
    handle.dispose();
  });

  testWidgets('large text scaling does not overflow on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpScreen(
      tester,
      data: {
        ..._alertWithLocation,
        'protectedPersonName': 'Marie-Christine Dupont-Laurent',
        'reminder': '1',
        'acknowledgementCount': '1',
      },
      theme: ThemeData(brightness: Brightness.dark),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('I\'m handling it'), findsOneWidget);
  });
}
