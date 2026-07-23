import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'screens/active_alert_screen.dart';
import 'screens/home_screen.dart';
import 'services/active_alert_presentation_state.dart';
import 'services/caregiver_backend_service.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  static const _activeAlertPollInterval = Duration(seconds: 5);

  final _backend = CaregiverBackendService();
  late PushNotificationService _pushService;
  Timer? _activeAlertPoller;
  bool _recoveringActiveAlert = false;
  bool _activeAlertRouteShowing = false;

  final _activeAlertPresentation = ActiveAlertPresentationState();
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushService = PushNotificationService(
      onAlertReceived: _handleAlert,
      onLinkRevoked: _handleLinkRevoked,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _stopActiveAlertPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startActiveAlertPolling();
      unawaited(_recoverActiveAlert());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopActiveAlertPolling();
    }
  }

  void _bootstrap() {
    unawaited(_refreshLinkState());
    unawaited(_initializePushNotifications());
    unawaited(_recoverActiveAlert());
    _startActiveAlertPolling();
  }

  Future<void> _refreshLinkState() async {
    try {
      await _backend.ensureRegistered();
      final linked = await _backend.refreshLinkedProtectedPersons();
      if (mounted) {
        setState(() => _linked = linked);
      }
    } catch (e) {
      final linked = await _backend.isLinked();
      if (mounted) {
        setState(() => _linked = _linked || linked);
      }
      developer.log('Device bootstrap skipped: $e', name: '_AppRootState');
    }
  }

  Future<void> _initializePushNotifications() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await _pushService.initialize();
      await _registerFcmToken(await _pushService.getFcmToken());
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerFcmToken);
    } catch (e) {
      developer.log('Push bootstrap skipped: $e', name: '_AppRootState');
    }
  }

  Future<void> _registerFcmToken(String? token) async {
    if (token == null) return;
    try {
      await _backend.registerPushToken(token);
      developer.log('FCM token registered', name: '_AppRootState');
    } catch (e) {
      // Not yet linked — token registration will fail if device is not caregiver type.
      // This is fine; we'll retry after linking.
      developer.log(
        'FCM token registration skipped: $e',
        name: '_AppRootState',
      );
    }
  }

  Future<void> _recoverActiveAlert() async {
    if (_recoveringActiveAlert) return;
    _recoveringActiveAlert = true;
    try {
      final alert = await _backend.getLatestActiveAlertData();
      if (alert != null) {
        _handleAlert(alert);
      } else if (mounted && _activeAlertPresentation.clearActive()) {
        setState(() {});
      }
    } catch (e) {
      developer.log('Active alert recovery skipped: $e', name: '_AppRootState');
    } finally {
      _recoveringActiveAlert = false;
    }
  }

  void _startActiveAlertPolling() {
    _activeAlertPoller ??= Timer.periodic(
      _activeAlertPollInterval,
      (_) => unawaited(_recoverActiveAlert()),
    );
  }

  void _stopActiveAlertPolling() {
    _activeAlertPoller?.cancel();
    _activeAlertPoller = null;
  }

  void _handleAlert(Map<String, dynamic> data) {
    if (!mounted) return;
    if (_activeAlertPresentation.show(data)) {
      unawaited(_reportAlertReceived(data));
      _presentActiveAlert(data);
    }
  }

  Future<void> _reportAlertReceived(Map<String, dynamic> data) async {
    final alertId = data['alertId'] as String?;
    if (alertId == null || alertId.isEmpty) return;

    try {
      await _backend.reportAlertReceived(alertId);
    } catch (error, stackTrace) {
      developer.log(
        'Alert receipt report failed for $alertId',
        name: '_AppRootState',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _presentActiveAlert(Map<String, dynamic> data) {
    if (_activeAlertRouteShowing) return;
    _activeAlertRouteShowing = true;

    void pushAlertRoute() {
      if (!mounted) {
        _activeAlertRouteShowing = false;
        return;
      }

      Navigator.of(context, rootNavigator: true)
          .push<void>(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => ActiveAlertScreen(
                alertData: data,
                onDismiss: () {
                  _activeAlertPresentation.dismissActive();
                  Navigator.of(context, rootNavigator: true).maybePop();
                },
              ),
            ),
          )
          .whenComplete(() {
            if (!mounted) return;
            _activeAlertRouteShowing = false;
            setState(_activeAlertPresentation.dismissActive);
          });
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      pushAlertRoute();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => pushAlertRoute());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleLinkRevoked() {
    if (!mounted) return;
    unawaited(_refreshLinkState());
  }

  void _onLinked() {
    setState(() => _linked = true);
    _pushService
        .getFcmToken()
        .then(_registerFcmToken)
        .catchError(
          (Object e) => developer.log(
            'Push token re-registration error: $e',
            name: '_AppRootState',
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return CaregiverHomeScreen(isLinked: _linked, onLinked: _onLinked);
  }
}
