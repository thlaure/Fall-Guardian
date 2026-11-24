import 'package:caregiver_app/screens/link_screen.dart';
import 'package:caregiver_app/screens/protected_persons_screen.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/fake_backend.dart';

void main() {
  testWidgets('load failure offers a working retry', (tester) async {
    final backend = FakeCaregiverBackend(protectedPersons: [marie])
      ..loadPersonsError = CaregiverApiException('offline');

    await tester.pumpWidget(testApp(ProtectedPersonsScreen(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load protected persons'), findsOneWidget);

    backend.loadPersonsError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Marie'), findsOneWidget);
  });

  testWidgets('unnamed persons get a numbered fallback label', (tester) async {
    final backend = FakeCaregiverBackend(
      protectedPersons: [
        const LinkedProtectedPerson(
          linkId: 'link-9',
          protectedDeviceId: 'abcdefghijkl',
          protectedDevicePlatform: 'android',
          protectedPersonName: null,
        ),
      ],
    );

    await tester.pumpWidget(testApp(ProtectedPersonsScreen(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text('Protected person 1'), findsOneWidget);
    expect(find.text('ANDROID device abcdefgh'), findsOneWidget);
  });

  testWidgets('removal failure keeps the person and explains it', (
    tester,
  ) async {
    var linksChanged = 0;
    final backend = FakeCaregiverBackend(protectedPersons: [marie])
      ..removeError = CaregiverApiException('offline');

    await tester.pumpWidget(
      testApp(
        ProtectedPersonsScreen(
          backend: backend,
          onLinksChanged: (_) => linksChanged++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Marie'), findsOneWidget);
    expect(find.textContaining('Failed to remove the link'), findsOneWidget);
    expect(linksChanged, 0);
  });

  testWidgets('successful removal reports the new link state', (tester) async {
    final changes = <bool>[];
    final backend = FakeCaregiverBackend(protectedPersons: [marie]);

    await tester.pumpWidget(
      testApp(
        ProtectedPersonsScreen(backend: backend, onLinksChanged: changes.add),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(changes, [false]);
    expect(find.textContaining('Marie'), findsWidgets);
  });

  testWidgets('adding a person through the FAB refreshes the list', (
    tester,
  ) async {
    var linked = 0;
    final backend = FakeCaregiverBackend();

    await tester.pumpWidget(
      testApp(
        ProtectedPersonsScreen(backend: backend, onLinked: () => linked++),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No protected persons yet'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(LinkScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Paul');
    await tester.enterText(find.byType(TextFormField).at(1), 'Thomas');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '669CBEC261CDDF65DD21F4D2A2452689',
    );
    await tester.ensureVisible(find.text('Add as Caregiver'));
    await tester.tap(find.text('Add as Caregiver'));
    await tester.pumpAndSettle();

    expect(linked, 1);
    expect(find.byType(LinkScreen), findsNothing);
    expect(find.text('Paul'), findsOneWidget);
  });
}
