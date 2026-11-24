import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/screens/home_screen.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:fall_guardian/services/device_pairing_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'home shows unlinked caregiver status when no caregiver is linked',
    (tester) async {
      await tester.pumpWidget(
        _app(
          HomeScreen(backendApi: _FakeBackendApiService(caregivers: const [])),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No caregiver linked'), findsOneWidget);
      expect(
        find.textContaining('no caregiver will be alerted yet'),
        findsOneWidget,
      );
      expect(find.text('Protected'), findsNothing);
    },
  );

  testWidgets('home shows protected status when a caregiver is linked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        HomeScreen(
          backendApi: _FakeBackendApiService(
            caregivers: const [
              {'id': 'caregiver-link-1'},
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Protected'), findsOneWidget);
    expect(find.textContaining('Fall detection is active'), findsOneWidget);
    expect(find.text('No caregiver linked'), findsNothing);
  });
  group('re-pairing required', () {
    testWidgets('shows a persistent warning and re-pairs on request', (
      tester,
    ) async {
      final state = DevicePairingState();
      var reconfigured = 0;
      final api = _FakeBackendApiService(
        caregivers: const [],
        repairRequiredFlag: true,
        state: state,
      );
      await tester.pumpWidget(
        _app(
          HomeScreen(
            backendApi: api,
            pairingState: state,
            onDeviceRepaired: () async => reconfigured++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Caregivers will NOT be notified'), findsOneWidget);
      expect(find.textContaining('new invitation'), findsWidgets);

      await tester.tap(find.text('Re-pair this phone'));
      await tester.pump();
      await tester.pump();

      expect(api.repairCalls, 1);
      expect(reconfigured, 1);
      expect(find.byKey(const Key('repair-required-banner')), findsNothing);
      expect(find.textContaining('Phone re-paired'), findsOneWidget);
    });

    testWidgets('a failed re-pair keeps the warning visible', (tester) async {
      final state = DevicePairingState();
      final api = _FakeBackendApiService(
        caregivers: const [],
        repairRequiredFlag: true,
        repairShouldFail: true,
        state: state,
      );
      await tester.pumpWidget(
        _app(HomeScreen(backendApi: api, pairingState: state)),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Re-pair this phone'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('repair-required-banner')), findsOneWidget);
      expect(find.textContaining('Re-pairing failed'), findsOneWidget);
    });

    testWidgets('appears as soon as any call flags the shared state', (
      tester,
    ) async {
      final state = DevicePairingState();
      await tester.pumpWidget(
        _app(
          HomeScreen(
            backendApi: _FakeBackendApiService(
              caregivers: const [],
              state: state,
            ),
            pairingState: state,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('repair-required-banner')), findsNothing);

      state.repairRequired.value = true;
      await tester.pump();

      expect(find.byKey(const Key('repair-required-banner')), findsOneWidget);
    });
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    required this.caregivers,
    this.repairRequiredFlag = false,
    this.repairShouldFail = false,
    this.state,
  });

  final List<Map<String, dynamic>> caregivers;
  bool repairRequiredFlag;
  final bool repairShouldFail;
  final DevicePairingState? state;
  int repairCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> getLinkedCaregivers() async => caregivers;

  @override
  Future<bool> isRepairRequired() async {
    state?.repairRequired.value = repairRequiredFlag;
    return repairRequiredFlag;
  }

  @override
  Future<void> repairDevice() async {
    repairCalls++;
    if (repairShouldFail) throw BackendApiException('down', statusCode: 503);
    repairRequiredFlag = false;
    state?.repairRequired.value = false;
  }
}
