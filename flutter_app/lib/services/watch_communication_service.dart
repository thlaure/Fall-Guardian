import 'package:flutter/services.dart';

typedef FallDetectedCallback = void Function(int timestamp);

/// Listens for fall events from the native watch layer
/// (Wear OS Data Layer on Android, WatchConnectivity on iOS).
class WatchCommunicationService {
  static const _channel = MethodChannel('fall_guardian/watch');

  FallDetectedCallback? _onFallDetected;

  WatchCommunicationService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  void setFallDetectedCallback(FallDetectedCallback callback) {
    _onFallDetected = callback;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onFallDetected') {
      final ts = (call.arguments as Map)['timestamp'] as int? ??
          DateTime.now().millisecondsSinceEpoch;
      _onFallDetected?.call(ts);
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _onFallDetected = null;
  }
}
