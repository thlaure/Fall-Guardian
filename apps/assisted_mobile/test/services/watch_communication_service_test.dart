import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      service.setFallDetectedCallback((timestamp) {
        receivedTimestamp = timestamp;
      });

      await simulateNativeCall('onFallDetected', {'timestamp': 1710000000000});

      expect(receivedTimestamp, 1710000000000);
      service.dispose();
    });

    test('onFallDetected falls back to now() when timestamp is missing',
        () async {
      final service = WatchCommunicationService();
      int? receivedTimestamp;
      service.setFallDetectedCallback((timestamp) {
        receivedTimestamp = timestamp;
      });

      final before = DateTime.now().millisecondsSinceEpoch;
      await simulateNativeCall('onFallDetected', <Object?, Object?>{});
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(receivedTimestamp, isNotNull);
      expect(receivedTimestamp! >= before && receivedTimestamp! <= after, isTrue);
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
      service.setFallDetectedCallback((_) => fallDetected = true);

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

    test('sendCancelAlert swallows platform errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR', message: 'watch unreachable');
      });

      // Must not throw.
      await WatchCommunicationService.sendCancelAlert();
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
