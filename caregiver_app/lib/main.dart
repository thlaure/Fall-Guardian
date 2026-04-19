import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'screens/active_alert_screen.dart';
import 'screens/home_screen.dart';
import 'services/caregiver_backend_service.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    developer.log('Firebase init skipped (no config): $e', name: 'main');
  }
  runApp(const CaregiverApp());
}

class CaregiverApp extends StatelessWidget {
  const CaregiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Guardian Caregiver',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: null,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  final _backend = CaregiverBackendService();
  late PushNotificationService _pushService;

  Map<String, dynamic>? _activeAlert;
  bool _ready = false;
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    _pushService = PushNotificationService(onAlertReceived: _handleAlert);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _backend.ensureRegistered();
      await _pushService.initialize();
      final token = await _pushService.getFcmToken();
      if (token != null) {
        try {
          await _backend.registerPushToken(token);
          developer.log('FCM token registered', name: '_AppRootState');
        } catch (e) {
          // Not yet linked — token registration will fail if device is not caregiver type.
          // This is fine; we'll retry after linking.
          developer.log('FCM token registration skipped: $e', name: '_AppRootState');
        }
      }
    } catch (e) {
      developer.log('Bootstrap error: $e', name: '_AppRootState');
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _handleAlert(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() => _activeAlert = data);
  }

  void _onLinked() {
    setState(() => _linked = true);
    // Re-register the FCM token now that we are linked
    _pushService.getFcmToken().then((token) {
      if (token != null) {
        _backend.registerPushToken(token).catchError(
          (e) => developer.log('Push token re-registration error: $e', name: '_AppRootState'),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_activeAlert != null) {
      return ActiveAlertScreen(
        alertData: _activeAlert!,
        onDismiss: () => setState(() => _activeAlert = null),
      );
    }

    return CaregiverHomeScreen(
      isLinked: _linked,
      onLinked: _onLinked,
    );
  }
}
