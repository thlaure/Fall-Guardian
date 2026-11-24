import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/l10n/app_localizations_en.dart';
import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/screens/fall_alert_screen.dart';
import 'package:fall_guardian/services/alert_coordinator.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _Clock implements Clock {
  _Clock(this._now);

  DateTime _now;
  Duration _elapsed = Duration.zero;

  void advance(Duration by) {
    _now = _now.add(by);
    _elapsed += by;
  }

  @override
  DateTime now() => _now;

  @override
  Duration elapsed() => _elapsed;
}

class _Backend implements AlertBackendGateway {
  _Backend({this.receipt, this.repairRequired = false});

  final FallAlertReceipt? receipt;
  final bool repairRequired;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> syncContacts(List<Contact> contacts) async {}

  @override
  Future<FallAlertReceipt?> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    if (repairRequired) throw DeviceRepairRequiredException(statusCode: 401);
    return receipt;
  }

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

class _Recorder implements FallEventRecorder {
  @override
  Future<void> add(FallEvent event) async {}
}

class _Location implements AlertLocationProvider {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class _Notifications implements AlertNotificationGateway {
  @override
  Future<void> cancelAll() async {}
}

class _Watch implements WatchCommandGateway {
  @override
  Future<void> sendCancelAlert({
    String? incidentId,
    int? fallTimestamp,
  }) async {}
}

class _Locale implements AlertLocaleResolver {
  @override
  AppLocalizations resolve() => AppLocalizationsEn();

  @override
  String languageCode() => 'en';
}

class _Ids implements IdGenerator {
  @override
  String newId() => 'id';
}

AlertCoordinator _coordinator(_Clock clock, _Backend backend) =>
    AlertCoordinator(
      eventRecorder: _Recorder(),
      locationProvider: _Location(),
      notificationGateway: _Notifications(),
      backendGateway: backend,
      watchGateway: _Watch(),
      localeResolver: _Locale(),
      clock: clock,
      idGenerator: _Ids(),
    );

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('countdown follows the server deadline returned by the API', (
    tester,
  ) async {
    final clock = _Clock(DateTime(2026, 7, 24, 12));
    final coordinator = _coordinator(
      clock,
      _Backend(
        receipt: const FallAlertReceipt(remainingGrace: Duration(seconds: 12)),
      ),
    );
    final timestamp = clock.now().millisecondsSinceEpoch;
    await coordinator.startAlert(timestamp);
    await tester.pumpWidget(
      _app(
        FallAlertScreen(
          fallTimestamp: timestamp,
          alertCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(coordinator.remainingCountdownSeconds, 12);
    expect(find.text('12'), findsOneWidget);
    expect(find.byKey(const Key('caregivers-being-notified')), findsNothing);

    coordinator.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'past the deadline the screen says caregivers are being notified and '
    'never shows negative time',
    (tester) async {
      final clock = _Clock(DateTime(2026, 7, 24, 12));
      final coordinator = _coordinator(clock, _Backend());
      final timestamp = clock.now().millisecondsSinceEpoch;
      await coordinator.startAlert(timestamp);
      await tester.pumpWidget(
        _app(
          FallAlertScreen(
            fallTimestamp: timestamp,
            alertCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump();

      // Monotonic clock jumps (e.g. app was suspended) without the deadline
      // timer having fired yet.
      clock.advance(const Duration(seconds: 40));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
      expect(
        find.text(
          'Cancellation window closed — caregivers are being notified.',
        ),
        findsOneWidget,
      );

      coordinator.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rejected device credentials are shown during the countdown', (
    tester,
  ) async {
    final clock = _Clock(DateTime(2026, 7, 24, 12));
    final coordinator = _coordinator(clock, _Backend(repairRequired: true));
    final timestamp = clock.now().millisecondsSinceEpoch;
    await tester.pumpWidget(
      _app(
        FallAlertScreen(
          fallTimestamp: timestamp,
          alertCoordinator: coordinator,
        ),
      ),
    );
    await coordinator.startAlert(timestamp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const Key('countdown-status-message')), findsOneWidget);
    expect(find.textContaining('Caregivers were NOT notified'), findsOneWidget);

    coordinator.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
