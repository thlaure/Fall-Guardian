import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/screens/contacts_screen.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('caregivers screen shows invite above linked caregivers', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      linkedCaregivers: [
        {'id': 'link-1', 'platform': 'ios'},
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContactsScreen(api: api),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Invite a caregiver'), findsOneWidget);
    expect(find.text('Caregiver 1'), findsOneWidget);
    expect(find.text('Add Contact'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    final inviteTop = tester.getTopLeft(find.text('Invite a caregiver')).dy;
    final caregiverTop = tester.getTopLeft(find.text('Caregiver 1')).dy;
    expect(inviteTop, lessThan(caregiverTop));
  });

  testWidgets('caregivers screen generates invite from the single FAB', (
    tester,
  ) async {
    final api = _FakeBackendApiService(linkedCaregivers: const []);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContactsScreen(api: api),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump();

    expect(api.invitesCreated, 1);
    expect(
        find.text('ABCD 1234 EFGH 5678 IJKL 9012 MNOP 3456'), findsOneWidget);
    expect(find.text('Generate Invite Code'), findsNothing);
  });
}

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({required this.linkedCaregivers});

  final List<Map<String, dynamic>> linkedCaregivers;
  int invitesCreated = 0;

  @override
  Future<List<Map<String, dynamic>>> getLinkedCaregivers() async {
    return linkedCaregivers;
  }

  @override
  Future<Map<String, dynamic>> createInvite() async {
    invitesCreated += 1;
    return {
      'code': 'ABCD1234EFGH5678IJKL9012MNOP3456',
      'expiresAt': '2026-06-21T10:00:00+00:00',
    };
  }

  @override
  Future<void> deleteLinkedCaregiver(String linkId) async {}
}
