import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/home_screen.dart';
import 'package:caregiver_app/screens/link_screen.dart';

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
    expect(find.text('Add protected person'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
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
    expect(find.text('Add another protected person'), findsOneWidget);
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
    await tester.enterText(find.byType(TextFormField), groupedCode);
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

    await tester.enterText(find.byType(TextFormField), 'ABC12345');
    await tester.tap(find.text('Add as Caregiver'));
    await tester.pump();

    expect(find.text('Enter the full 32-character code'), findsOneWidget);
  });
}
