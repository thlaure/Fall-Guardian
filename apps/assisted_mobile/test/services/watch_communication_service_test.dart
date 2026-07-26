import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fall_guardian/services/companion_enrollment_service.dart';
import 'package:fall_guardian/services/watch_communication_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fall_guardian/watch');
  const codec = StandardMethodCodec();

  Future<void> simulateNativeCall(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'fall_guardian/watch',
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('WatchCommunicationService', () {
    test('onFallDetected delivers the native timestamp to the callback',
        () async {
      final service = WatchCommunicationService();
      int? receivedTimestamp;
      service.setFallDetectedCallback((timestamp, _) {
        receivedTimestamp = timestamp;
      });

      await simulateNativeCall('onFallDetected', {'timestamp': 1710000000000});

      expect(receivedTimestamp, 1710000000000);
      service.dispose();
    });

    test('onFallDetected forwards the native idempotency key', () async {
      final service = WatchCommunicationService();
      String? receivedClientAlertId;
      service.setFallDetectedCallback((_, clientAlertId) {
        receivedClientAlertId = clientAlertId;
      });

      await simulateNativeCall('onFallDetected', {
        'timestamp': 1710000000000,
        'clientAlertId': 'wear-os-1710000000000',
      });

      expect(receivedClientAlertId, 'wear-os-1710000000000');
      service.dispose();
    });

    test('onFallDetected falls back to now() when timestamp is missing',
        () async {
      final service = WatchCommunicationService();
      int? receivedTimestamp;
      service.setFallDetectedCallback((timestamp, _) {
        receivedTimestamp = timestamp;
      });

      final before = DateTime.now().millisecondsSinceEpoch;
      await simulateNativeCall('onFallDetected', <Object?, Object?>{});
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(receivedTimestamp, isNotNull);
      expect(
          receivedTimestamp! >= before && receivedTimestamp! <= after, isTrue);
      service.dispose();
    });

    test('onAlertCancelled invokes the cancel callback', () async {
      final service = WatchCommunicationService();
      var cancelled = false;
      service.setCancelAlertCallback(() => cancelled = true);

      await simulateNativeCall('onAlertCancelled');

      expect(cancelled, isTrue);
      service.dispose();
    });

    test('unknown native method is a no-op', () async {
      final service = WatchCommunicationService();

      await simulateNativeCall('somethingElse');

      // No callback fired and no exception thrown.
      service.dispose();
    });

    test('dispose clears the channel handler', () async {
      final service = WatchCommunicationService();
      var fallDetected = false;
      service.setFallDetectedCallback((_, __) => fallDetected = true);

      service.dispose();

      // With no handler registered, this message becomes a no-op from the
      // engine's point of view; the callback must not fire.
      await simulateNativeCall('onFallDetected', {'timestamp': 1});
      expect(fallDetected, isFalse);
    });

    test('sendCancelAlert invokes the channel method', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });

      await WatchCommunicationService.sendCancelAlert();

      expect(captured?.method, 'sendCancelAlert');
    });

    test('configureNativeAlertRelay sends only the backend URL', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });

      await WatchCommunicationService.configureNativeAlertRelay(
        'https://api.example.test',
      );

      expect(captured?.method, 'configureNativeAlertRelay');
      expect(captured?.arguments, {
        'baseUrl': 'https://api.example.test',
      });
    });

    test('sendCancelAlert swallows platform errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR', message: 'watch unreachable');
      });

      // Must not throw.
      await WatchCommunicationService.sendCancelAlert();
    });

    test('sendCompanionEnrollment invokes versioned channel contract',
        () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });
      final enrollment = CompanionEnrollment(
        token: 'a' * 64,
        expiresAt: DateTime.parse('2026-07-25T10:05:00Z'),
      );

      await WatchCommunicationService.sendCompanionEnrollment(
        CompanionEnrollmentMessage(
          platform: CompanionPlatform.watchOS,
          enrollment: enrollment,
        ),
      );

      expect(captured?.method, 'sendCompanionEnrollment');
      expect(captured?.arguments, {
        'type': 'companionEnrollment',
        'schemaVersion': 1,
        'platform': 'watchos',
        'enrollmentToken': 'a' * 64,
        'expiresAt': '2026-07-25T10:05:00.000Z',
      });
    });

    test('sendCompanionEnrollment exposes native delivery errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'WATCH_UNAVAILABLE');
      });
      final enrollment = CompanionEnrollment(
        token: 'a' * 64,
        expiresAt: DateTime.parse('2026-07-25T10:05:00Z'),
      );

      await expectLater(
        WatchCommunicationService.sendCompanionEnrollment(
          CompanionEnrollmentMessage(
            platform: CompanionPlatform.watchOS,
            enrollment: enrollment,
          ),
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('pushThresholds sends the threshold payload', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });

      await WatchCommunicationService.pushThresholds(
        freeFall: 0.6,
        impact: 2.5,
        tilt: 60,
        freeFallMs: 400,
      );

      expect(captured?.method, 'sendThresholds');
      expect(captured?.arguments, {
        'thresh_freefall': 0.6,
        'thresh_impact': 2.5,
        'thresh_tilt': 60,
        'thresh_freefall_ms': 400,
      });
    });

    test('pushThresholds swallows platform errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR', message: 'watch unreachable');
      });

      // Must not throw.
      await WatchCommunicationService.pushThresholds(
        freeFall: 0.6,
        impact: 2.5,
        tilt: 60,
        freeFallMs: 400,
      );
    });
  });
}
