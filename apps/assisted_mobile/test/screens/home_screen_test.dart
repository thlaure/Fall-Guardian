import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/screens/home_screen.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'home shows unlinked caregiver status when no caregiver is linked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
          HomeScreen(backendApi: _FakeBackendApiService(caregivers: const []))),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No caregiver linked'), findsOneWidget);
    expect(find.textContaining('no caregiver will be alerted yet'),
        findsOneWidget);
    expect(find.text('Protected'), findsNothing);
  });

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
  _FakeBackendApiService({required this.caregivers});

  final List<Map<String, dynamic>> caregivers;

  @override
  Future<List<Map<String, dynamic>>> getLinkedCaregivers() async => caregivers;
}
