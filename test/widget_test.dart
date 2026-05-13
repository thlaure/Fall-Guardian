import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caregiver_app/l10n/app_localizations.dart';
import 'package:caregiver_app/screens/home_screen.dart';

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
    expect(find.text('Link with Protected Person'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
  });
}
