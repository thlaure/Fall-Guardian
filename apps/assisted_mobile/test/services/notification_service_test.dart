import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/src/platform_flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The plugin normally registers this via its native plugin-registration
  // hook, which doesn't run under plain `flutter test`. `flutter_test`
  // defaults defaultTargetPlatform to android, so register the Android
  // channel-backed implementation manually so the mocked channel below is
  // actually exercised instead of the package's no-op safety net.
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'requestNotificationsPermission':
          return true;
        case 'show':
          return null;
        case 'cancelAll':
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NotificationService', () {
    test('initialize registers the Android channel and requests permission',
        () async {
      final service = NotificationService();

      await service.initialize();

      // On the macOS test host, Platform.isIOS is false, so the Android
      // initialization branch runs regardless of the target platform.
      expect(calls, contains('initialize'));
      expect(calls, contains('requestNotificationsPermission'));
    });

    test('initialize is a no-op on the second call', () async {
      final service = NotificationService();

      await service.initialize();
      calls.clear();
      await service.initialize();

      expect(calls, isEmpty);
    });

    test('showFallDetectedNotification shows a notification via the plugin',
        () async {
      final service = NotificationService();

      await service.showFallDetectedNotification(
        title: 'Fall detected',
        body: 'Tap to open',
      );

      expect(calls, contains('show'));
    });

    test('cancelAll clears active notifications', () async {
      final service = NotificationService();

      await service.cancelAll();

      expect(calls, contains('cancelAll'));
    });

    test('cancelAll swallows plugin errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR', message: 'no notifications');
      });

      final service = NotificationService();

      // Must not throw.
      await service.cancelAll();
    });
  });
}
