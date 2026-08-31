import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget app({required bool wearOs, double bottomInset = 0}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: SettingsScreen(wearOsOverride: wearOs),
        ),
      );

  testWidgets('watch connection feature is absent', (tester) async {
    await tester.pumpWidget(app(wearOs: true));
    await tester.pumpAndSettle();

    expect(find.text('Watch connection'), findsNothing);
    expect(find.text('Connect watch'), findsNothing);
    expect(find.text('Fall Detection Thresholds'), findsOneWidget);
  });

  testWidgets('custom detection thresholds are hidden outside Wear OS',
      (tester) async {
    await tester.pumpWidget(app(wearOs: false));
    await tester.pumpAndSettle();

    expect(find.text('Fall Detection Thresholds'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('reset button keeps bottom margin above system navigation',
      (tester) async {
    await tester.pumpWidget(app(wearOs: true, bottomInset: 32));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.padding, const EdgeInsets.fromLTRB(20, 20, 20, 52));

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Reset to defaults'), findsOneWidget);
  });
}
