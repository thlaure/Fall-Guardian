import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/home_screen.dart';
import 'package:caregiver_app/screens/link_screen.dart';
import 'package:caregiver_app/screens/protected_persons_screen.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';

void main() {
  testWidgets('renders caregiver scaffold home', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CaregiverHomeScreen(isLinked: false),
      ),
    );
    await tester.pump();

    expect(find.text('Fall Guardian Caregiver'), findsOneWidget);
    expect(find.text('Not Linked Yet'), findsOneWidget);
    expect(find.text('View protected persons'), findsOneWidget);
    expect(find.text('Add protected person'), findsNothing);
    expect(find.text('Fall History'), findsOneWidget);
  });

  testWidgets('updates the home status when the linked state changes', (
    tester,
  ) async {
    Widget buildHome({required bool isLinked}) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CaregiverHomeScreen(isLinked: isLinked),
      );
    }

    await tester.pumpWidget(buildHome(isLinked: false));
    await tester.pump();

    expect(find.text('Not Linked Yet'), findsOneWidget);

    await tester.pumpWidget(buildHome(isLinked: true));
    await tester.pump();

    expect(find.text('Monitoring Active'), findsOneWidget);
    expect(find.text('View protected persons'), findsOneWidget);
  });

  testWidgets('protected persons screen lists people with add FAB', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProtectedPersonsScreen(
          backend: _FakeCaregiverBackendService([
            const LinkedProtectedPerson(
              protectedDeviceId: 'protected-device-1',
              protectedDevicePlatform: 'ios',
              protectedPersonName: 'Marie',
            ),
            const LinkedProtectedPerson(
              protectedDeviceId: 'protected-device-2',
              protectedDevicePlatform: 'android',
              protectedPersonName: 'Paul',
            ),
          ]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Protected persons'), findsOneWidget);
    expect(find.text('2 protected persons'), findsOneWidget);
    expect(find.text('Marie'), findsOneWidget);
    expect(find.text('Paul'), findsOneWidget);
    expect(find.text('Device ID'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('link screen accepts the grouped 32-character invite format', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: LinkScreen(onLinked: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('32-character invite code'), findsOneWidget);

    const groupedCode = '669C BEC2 61CD DF65 DD21 F4D2 A245 2689';
    await tester.enterText(find.byType(TextFormField).at(0), 'Marie');
    await tester.enterText(find.byType(TextFormField).at(1), 'Thomas');
    await tester.enterText(find.byType(TextFormField).last, groupedCode);
    await tester.pump();

    expect(find.text(groupedCode), findsOneWidget);
    expect(find.text('Enter the full 32-character code'), findsNothing);
  });

  testWidgets('link screen rejects short legacy invite codes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: LinkScreen(onLinked: () {}),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, 'Marie');
    await tester.enterText(find.byType(TextFormField).at(1), 'Thomas');
    await tester.enterText(find.byType(TextFormField).last, 'ABC12345');
    await tester.ensureVisible(find.text('Add as Caregiver'));
    await tester.tap(find.text('Add as Caregiver'));
    await tester.pump();

    expect(find.text('Enter the full 32-character code'), findsOneWidget);
  });
}

class _FakeCaregiverBackendService extends CaregiverBackendService {
  _FakeCaregiverBackendService(this.protectedPersons);

  final List<LinkedProtectedPerson> protectedPersons;

  @override
  Future<List<LinkedProtectedPerson>> getLinkedProtectedPersons() async {
    return protectedPersons;
  }
}
