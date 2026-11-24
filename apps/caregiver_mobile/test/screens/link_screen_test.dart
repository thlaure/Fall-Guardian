import 'dart:async';

import 'package:caregiver_app/screens/link_screen.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/fake_backend.dart';

void main() {
  const groupedCode = '669c bec2-61cd df65 dd21 f4d2 a245 2689';

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String person = ' Marie ',
    String caregiver = 'Thomas',
    String code = groupedCode,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), person);
    await tester.enterText(find.byType(TextFormField).at(1), caregiver);
    await tester.enterText(find.byType(TextFormField).at(2), code);
    await tester.ensureVisible(find.text('Add as Caregiver'));
    await tester.tap(find.text('Add as Caregiver'));
    await tester.pump();
  }

  Future<FakeCaregiverBackend> pumpLinkScreen(
    WidgetTester tester, {
    VoidCallback? onLinked,
  }) async {
    final backend = FakeCaregiverBackend();
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LinkScreen(onLinked: onLinked ?? () {}, backend: backend),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return backend;
  }

  testWidgets('accepts a normalized invite code and closes on success', (
    tester,
  ) async {
    var linked = 0;
    final backend = await pumpLinkScreen(tester, onLinked: () => linked++);
    backend.acceptGate = Completer<void>();

    await fillAndSubmit(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(backend.acceptedInvites.single, (
      '669CBEC261CDDF65DD21F4D2A2452689',
      'Marie',
      'Thomas',
    ));

    backend.acceptGate!.complete();
    await tester.pumpAndSettle();

    expect(linked, 1);
    expect(find.byType(LinkScreen), findsNothing);
  });

  testWidgets('validates names and code before calling the API', (
    tester,
  ) async {
    final backend = await pumpLinkScreen(tester);

    await fillAndSubmit(tester, person: 'M', caregiver: ' ', code: 'ABC12345');

    expect(
      find.text('Enter a name with at least 2 characters'),
      findsOneWidget,
    );
    expect(
      find.text('Enter your name with at least 2 characters'),
      findsOneWidget,
    );
    expect(find.text('Enter the full 32-character code'), findsOneWidget);
    expect(backend.acceptedInvites, isEmpty);
  });

  testWidgets('shows a specific message for unknown or expired codes', (
    tester,
  ) async {
    final backend = await pumpLinkScreen(tester);
    backend.acceptError = CaregiverApiException('nope', statusCode: 404);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Code not found or expired'), findsOneWidget);
    expect(find.byType(LinkScreen), findsOneWidget);
  });

  testWidgets('shows the status code for other API failures', (tester) async {
    final backend = await pumpLinkScreen(tester);
    backend.acceptError = CaregiverApiException('boom', statusCode: 500);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('(500)'), findsOneWidget);
  });

  testWidgets('shows a connection error for network failures', (tester) async {
    final backend = await pumpLinkScreen(tester);
    backend.acceptError = StateError('socket closed');

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Connection error'), findsOneWidget);
    expect(find.text('Add as Caregiver'), findsOneWidget);
  });
}
