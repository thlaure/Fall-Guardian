import 'package:fall_guardian/l10n/app_localizations.dart';
import 'package:fall_guardian/screens/settings_screen.dart';
import 'package:fall_guardian/services/companion_enrollment_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements CompanionEnrollmentBackendGateway {
  @override
  Future<CompanionEnrollment> createCompanionEnrollment(
    CompanionPlatform platform,
  ) async {
    return CompanionEnrollment(
      token: 'a' * 64,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('connect action enters waiting state after token is handed off',
      (tester) async {
    CompanionEnrollmentMessage? sent;
    final coordinator = CompanionEnrollmentCoordinator(
      backend: _FakeBackend(),
      sendToWatch: (message) async => sent = message,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          enrollmentCoordinator: coordinator,
          platformOverride: CompanionPlatform.watchOS,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect watch'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for the watch to finish setup'), findsOneWidget);
    expect(sent?.platform, CompanionPlatform.watchOS);
    expect(sent?.toMap()['schemaVersion'], 1);
  });

  testWidgets('native delivery failure offers retry', (tester) async {
    final coordinator = CompanionEnrollmentCoordinator(
      backend: _FakeBackend(),
      sendToWatch: (_) => throw StateError('watch unavailable'),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          enrollmentCoordinator: coordinator,
          platformOverride: CompanionPlatform.watchOS,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect watch'));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text(
        'Could not send setup to the watch. Check that it is nearby.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'missing watch app reports the actionable cause, not the generic '
      'nearby hint', (tester) async {
    final coordinator = CompanionEnrollmentCoordinator(
      backend: _FakeBackend(),
      sendToWatch: (_) => throw PlatformException(
        code: 'WATCH_UNAVAILABLE',
        message: 'No paired Apple Watch can receive enrollment.',
        details: 'watch_app_not_installed',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          enrollmentCoordinator: coordinator,
          platformOverride: CompanionPlatform.watchOS,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect watch'));
    await tester.pumpAndSettle();

    expect(
      find.text('Install Fall Guardian on your watch, then try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an unrecognised native cause still shows a message',
      (tester) async {
    final coordinator = CompanionEnrollmentCoordinator(
      backend: _FakeBackend(),
      sendToWatch: (_) => throw PlatformException(
        code: 'WATCH_UNAVAILABLE',
        details: 'some_future_reason',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          enrollmentCoordinator: coordinator,
          platformOverride: CompanionPlatform.watchOS,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect watch'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not send setup to the watch. Check that it is nearby.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('waiting state expires and offers a fresh enrollment',
      (tester) async {
    final backend = _FakeBackend();
    final coordinator = CompanionEnrollmentCoordinator(
      backend: backend,
      sendToWatch: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          enrollmentCoordinator: coordinator,
          platformOverride: CompanionPlatform.watchOS,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect watch'));
    await tester.pump();

    await tester.pump(const Duration(minutes: 5, seconds: 1));

    expect(find.text('Watch setup expired. Try again.'), findsOneWidget);
  });
}
