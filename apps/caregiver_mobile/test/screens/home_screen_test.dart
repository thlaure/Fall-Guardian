import 'package:caregiver_app/screens/alert_history_screen.dart';
import 'package:caregiver_app/screens/home_screen.dart';
import 'package:caregiver_app/screens/protected_persons_screen.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/fake_backend.dart';

void main() {
  testWidgets('shows the linked count and syncs the link state up', (
    tester,
  ) async {
    final linkStates = <bool>[];
    final backend = FakeCaregiverBackend(protectedPersons: [marie]);

    await tester.pumpWidget(
      testApp(
        CaregiverHomeScreen(
          isLinked: false,
          backend: backend,
          onLinkStateChanged: linkStates.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 protected person'), findsOneWidget);
    expect(find.text('Monitoring Active'), findsOneWidget);
    expect(linkStates, [true]);
  });

  testWidgets('keeps the given state when the count cannot be loaded', (
    tester,
  ) async {
    final backend = FakeCaregiverBackend()
      ..loadPersonsError = CaregiverApiException('offline');

    await tester.pumpWidget(
      testApp(CaregiverHomeScreen(isLinked: true, backend: backend)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monitoring Active'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ protected person')), findsNothing);
  });

  testWidgets('history is disabled until a person is linked', (tester) async {
    final backend = FakeCaregiverBackend();

    await tester.pumpWidget(
      testApp(CaregiverHomeScreen(isLinked: false, backend: backend)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fall History'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertHistoryScreen), findsNothing);
  });

  testWidgets('opens history with the shared backend when linked', (
    tester,
  ) async {
    final backend = FakeCaregiverBackend(protectedPersons: [marie]);

    await tester.pumpWidget(
      testApp(CaregiverHomeScreen(isLinked: true, backend: backend)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fall History'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertHistoryScreen), findsOneWidget);
    expect(find.text('No fall alerts yet'), findsOneWidget);
  });

  testWidgets('removing the last person from the list unlinks home', (
    tester,
  ) async {
    final linkStates = <bool>[];
    final backend = FakeCaregiverBackend(protectedPersons: [marie]);

    await tester.pumpWidget(
      testApp(
        CaregiverHomeScreen(
          isLinked: true,
          backend: backend,
          onLinkStateChanged: linkStates.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View protected persons'));
    await tester.pumpAndSettle();
    expect(find.byType(ProtectedPersonsScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Not Linked Yet'), findsOneWidget);
    expect(linkStates.last, isFalse);
  });

  testWidgets('linking from the list notifies and confirms', (tester) async {
    var linked = 0;
    final backend = FakeCaregiverBackend();

    await tester.pumpWidget(
      testApp(
        CaregiverHomeScreen(
          isLinked: false,
          backend: backend,
          onLinked: () => linked++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View protected persons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
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
    expect(find.textContaining('Linked successfully'), findsOneWidget);
  });
}
