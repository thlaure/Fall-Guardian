import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'firebase_options.dart';

import 'l10n/app_localizations.dart';
import 'screens/active_alert_screen.dart';
import 'screens/home_screen.dart';
import 'services/active_alert_presentation_state.dart';
import 'services/caregiver_backend_service.dart';
import 'services/caregiver_secure_storage.dart';
import 'services/foreground_migration_gate.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CaregiverApp());
}

class CaregiverApp extends StatelessWidget {
  const CaregiverApp({super.key, this.backend, this.pushService});

  /// Test seams; production builds use the real backend and FCM.
  final CaregiverBackendService? backend;
  final PushNotificationService Function({
    required void Function(Map<String, dynamic> data) onAlertReceived,
    required void Function() onLinkRevoked,
  })?
  pushService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Guardian Caregiver',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        AppLocalizations.delegate,
        // Material, Cupertino and Widgets delegates (material_ui package).
        ...GlobalMaterialLocalizations.delegates,
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
      home: _AppRoot(backend: backend, pushService: pushService),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({this.backend, this.pushService});

  final CaregiverBackendService? backend;
  final PushNotificationService Function({
    required void Function(Map<String, dynamic> data) onAlertReceived,
    required void Function() onLinkRevoked,
  })?
  pushService;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  static const _activeAlertPollInterval = Duration(seconds: 5);

  late final CaregiverBackendService _backend =
      widget.backend ?? CaregiverBackendService();
  late PushNotificationService _pushService;

  /// Migrates legacy keychain items so background push handling can report
  /// alert receipt while the iPhone is locked. Only runs in the foreground:
  /// a background push launch on a locked phone cannot read legacy items.
  late final _secureStorageMigration = ForegroundMigrationGate(
    migrate: _backend.migrateSecureStorage,
    isForeground: () =>
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
  );

  /// Set when the link refresh could not run (e.g. locked keychain during a
  /// background launch) so it is retried on the next resume.
  bool _linkRefreshPending = false;
  Timer? _activeAlertPoller;
  bool _recoveringActiveAlert = false;
  bool _activeAlertRouteShowing = false;

  final _activeAlertPresentation = ActiveAlertPresentationState();
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushService = (widget.pushService ?? PushNotificationService.new)(
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
      unawaited(_onResumed());
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

  Future<void> _onResumed() async {
    await _secureStorageMigration.ensure();
    if (_linkRefreshPending) await _refreshLinkState();
    await _recoverActiveAlert();
  }

  Future<void> _refreshLinkState() async {
    await _secureStorageMigration.ensure();
    try {
      await _backend.ensureRegistered();
      final linked = await _backend.refreshLinkedProtectedPersons();
      _linkRefreshPending = false;
      if (mounted) {
        setState(() => _linked = linked);
      }
    } on SecureStorageUnavailableException catch (e) {
      // Credentials exist but are locked: keep the current state and never
      // register a replacement device. Retried on the next resume.
      _linkRefreshPending = true;
      developer.log('Device bootstrap deferred: $e', name: '_AppRootState');
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
      await _secureStorageMigration.ensure();
      await _registerFcmToken(await _pushService.getFcmToken());
      _pushService.onTokenRefresh.listen(_registerFcmToken);
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
      await _secureStorageMigration.ensure();
      // Oldest first so alerts are presented in the order they happened.
      final alerts = (await _backend.getActiveAlertsData()).reversed.toList();
      if (alerts.isNotEmpty) {
        alerts.forEach(_handleAlert);
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
    }
    // Presents the queue front; no-op while an alert route is visible (the
    // visible screen picks up newer data through its live listenable).
    _presentActiveAlert();
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

  void _presentActiveAlert() {
    final data = _activeAlertPresentation.activeAlert;
    final liveAlert = _activeAlertPresentation.activeAlertListenable;
    if (_activeAlertRouteShowing || data == null) return;
    _activeAlertRouteShowing = true;

    void pushAlertRoute() {
      if (!mounted) {
        _activeAlertRouteShowing = false;
        return;
      }

      var dismissed = false;
      // Dismiss only the alert this route shows: the queue may have been
      // cleared and refilled by polling while the screen was open.
      void dismissShownAlert() {
        if (ActiveAlertPresentationState.alertId(
              _activeAlertPresentation.activeAlert ?? const {},
            ) ==
            ActiveAlertPresentationState.alertId(data)) {
          _activeAlertPresentation.dismissActive();
        }
      }

      Navigator.of(context, rootNavigator: true)
          .push<void>(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => ValueListenableBuilder<int>(
                // Alerts for other people can arrive while this one is open.
                valueListenable:
                    _activeAlertPresentation.waitingCountListenable,
                builder: (_, waitingCount, _) => ActiveAlertScreen(
                  alertData: data,
                  liveAlert: liveAlert,
                  backend: _backend,
                  waitingCount: waitingCount,
                  onDismiss: () {
                    if (dismissed) return;
                    dismissed = true;
                    dismissShownAlert();
                    Navigator.of(context, rootNavigator: true).maybePop();
                  },
                ),
              ),
            ),
          )
          .whenComplete(() {
            if (!mounted) return;
            _activeAlertRouteShowing = false;
            // Back gesture closes without onDismiss: still dismiss the alert
            // that was shown (only if it is still the queue front).
            if (!dismissed) dismissShownAlert();
            setState(() {});
            // Next alert for another protected person, if any.
            _presentActiveAlert();
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

  void _onLinkStateChanged(bool linked) {
    if (!mounted) return;
    setState(() => _linked = linked);
  }

  @override
  Widget build(BuildContext context) {
    return CaregiverHomeScreen(
      backend: _backend,
      isLinked: _linked,
      onLinked: _onLinked,
      onLinkStateChanged: _onLinkStateChanged,
    );
  }
}
