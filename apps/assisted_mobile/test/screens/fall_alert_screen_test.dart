import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/l10n/app_localizations_en.dart';
import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/screens/fall_alert_screen.dart';
import 'package:fall_guardian/services/alert_coordinator.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/alert_runtime.dart';
import 'package:geolocator/geolocator.dart';

AlertCoordinator _coordinator() => AlertCoordinator(
      eventRecorder: _FakeEventRecorder(),
      locationProvider: _FakeLocationProvider(),
      notificationGateway: _FakeNotificationGateway(),
      backendGateway: _FakeBackendGateway(),
      watchGateway: _FakeWatchGateway(),
      localeResolver: _EnglishLocaleResolver(),
      clock: SystemClock(),
      idGenerator: const UuidGenerator(),
    );

class _FakeEventRecorder implements FallEventRecorder {
  @override
  Future<void> add(FallEvent event) async {}
}

class _FakeLocationProvider implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class _FakeNotificationGateway implements AlertNotificationGateway {
  @override
  Future<void> cancelAll() async {}
}

class _FakeBackendGateway implements AlertBackendGateway {
  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> syncContacts(List<Contact> contacts) async {}

  @override
  Future<void> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {}

  @override
  Future<void> recordCancelledFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {}

  @override
  Future<void> cancelFallAlert({required String clientAlertId}) async {}

  @override
  Future<void> attachLocation({
    required String clientAlertId,
    required double latitude,
    required double longitude,
  }) async {}
}

class _FakeWatchGateway implements WatchCommandGateway {
  @override
  Future<void> sendCancelAlert() async {}
}

class _EnglishLocaleResolver implements AlertLocaleResolver {
  @override
  AppLocalizations resolve() => AppLocalizationsEn();

  @override
  String languageCode() => 'en';
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

FallAlertScreen _screen(int timestamp, AlertCoordinator coordinator) =>
    FallAlertScreen(
      fallTimestamp: timestamp,
      alertCoordinator: coordinator,
    );

void main() {
  int freshFallTimestamp() => DateTime.now().millisecondsSinceEpoch + 200;
  final secureStore = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    // Silence platform calls from flutter_local_notifications in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/secure_storage'),
      (call) async {
        final key =
            (call.arguments as Map<Object?, Object?>?)?['key'] as String?;
        switch (call.method) {
          case 'read':
            return key != null ? secureStore[key] : null;
          case 'write':
            final value =
                (call.arguments as Map<Object?, Object?>?)?['value'] as String?;
            if (key != null && value != null) {
              secureStore[key] = value;
            }
            return null;
          case 'delete':
            if (key != null) secureStore.remove(key);
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/watch'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('fall_guardian/secure_storage'),
      null,
    );
  });

  group('FallAlertScreen', () {
    testWidgets('shows 30-second countdown on launch', (tester) async {
      final coordinator = _coordinator();
      await tester.pumpWidget(
        _app(_screen(freshFallTimestamp(), coordinator)),
      );
      await tester.pump();
      expect(find.text('30'), findsOneWidget);
      coordinator.dispose();
    });

    testWidgets('shows warning icon and cancel button', (tester) async {
      final coordinator = _coordinator();
      await tester.pumpWidget(
        _app(_screen(freshFallTimestamp(), coordinator)),
      );
      await tester.pump();
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      coordinator.dispose();
    });

    testWidgets('countdown ignores an untrusted wall-clock fall timestamp', (
      tester,
    ) async {
      final coordinator = _coordinator();
      final oldTimestamp = DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 5).inMilliseconds;
      await tester.pumpWidget(
        _app(_screen(oldTimestamp, coordinator)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('30').evaluate().isNotEmpty ||
            find.text('29').evaluate().isNotEmpty,
        isTrue,
      );
      coordinator.dispose();
    });

    testWidgets('countdown reaches 0 and transitions to sending state', (
      tester,
    ) async {
      final coordinator = _coordinator();
      final timestamp = freshFallTimestamp();
      await coordinator.startAlert(timestamp);
      await tester.pumpWidget(_app(_screen(timestamp, coordinator)));
      await tester.pump();
      expect(find.text('30'), findsOneWidget);

      // Advance to 0
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // After countdown completes _sendAlert fires; it will be in _sending=true
      // state (showing spinner) before async location/SMS complete.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      coordinator.dispose();
    });

    testWidgets('cancel during countdown prevents sendAlert from running', (
      tester,
    ) async {
      final coordinator = _coordinator();
      final timestamp = freshFallTimestamp();
      await coordinator.startAlert(timestamp);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _screen(timestamp, coordinator),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();

      // Advance a few seconds then cancel
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byIcon(Icons.check_circle));
      // Let async cancel chain complete without waiting for the repeating pulse
      // animation to "settle".
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Cancellation should prevent the coordinator from entering the timeout
      // send flow, even if the widget tree takes another frame to unwind.
      expect(coordinator.currentState, isNull);
      coordinator.dispose();
    });

    testWidgets('tapping cancel pops the screen', (tester) async {
      final coordinator = _coordinator();
      final timestamp = freshFallTimestamp();
      await coordinator.startAlert(timestamp);
      // Push FallAlertScreen on top of a home screen so we can verify the pop.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _screen(timestamp, coordinator),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      // Pump twice: once for the initial frame, once to load localizations.
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pump(); // trigger navigation
      await tester.pump(); // complete transition

      expect(find.byType(FallAlertScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump(); // trigger async cancel + pop
      await tester.pump(const Duration(milliseconds: 200)); // complete pop

      expect(find.byType(FallAlertScreen), findsNothing);
      coordinator.dispose();
    });

    testWidgets('remote cancel does not send cancel back to watch', (
      tester,
    ) async {
      final coordinator = _coordinator();
      final timestamp = freshFallTimestamp();
      await coordinator.startAlert(timestamp);
      final watchCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('fall_guardian/watch'),
        (call) async {
          watchCalls.add(call);
          return null;
        },
      );

      await tester.pumpWidget(
        _app(_screen(timestamp, coordinator)),
      );
      await tester.pump();

      await coordinator.cancelFromWatch();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(FallAlertScreen), findsNothing);
      expect(
        watchCalls.where((call) => call.method == 'sendCancelAlert'),
        isEmpty,
      );
      coordinator.dispose();
    });
  });
}
