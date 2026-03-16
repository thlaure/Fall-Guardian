import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/fall_alert_screen.dart';
import 'services/watch_communication_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();
  runApp(const FallGuardianApp());
}

class FallGuardianApp extends StatefulWidget {
  const FallGuardianApp({super.key});

  @override
  State<FallGuardianApp> createState() => _FallGuardianAppState();
}

class _FallGuardianAppState extends State<FallGuardianApp> {
  final _watchService = WatchCommunicationService();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _watchService.setFallDetectedCallback(_onFallDetected);
  }

  void _onFallDetected(int timestamp) async {
    await NotificationService().showFallDetectedNotification();

    // Navigate to alert screen on top of whatever is showing
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => FallAlertScreen(fallTimestamp: timestamp),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  void dispose() {
    _watchService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Fall Guardian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF533483),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      home: const HomeScreen(),
    );
  }
}
