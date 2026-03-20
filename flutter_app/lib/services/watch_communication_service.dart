import 'package:flutter/services.dart';

typedef FallDetectedCallback = void Function(int timestamp);
typedef CancelAlertCallback = void Function();

/// Listens for fall/cancel events from the native watch layer
/// (Wear OS Data Layer on Android, WatchConnectivity on iOS).
class WatchCommunicationService {
  static const _channel = MethodChannel('fall_guardian/watch');

  FallDetectedCallback? _onFallDetected;
  CancelAlertCallback? _onCancelAlert;

  WatchCommunicationService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  void setFallDetectedCallback(FallDetectedCallback callback) {
    _onFallDetected = callback;
  }

  void setCancelAlertCallback(CancelAlertCallback callback) {
    _onCancelAlert = callback;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onFallDetected':
        final ts = (call.arguments as Map)['timestamp'] as int? ??
            DateTime.now().millisecondsSinceEpoch;
        _onFallDetected?.call(ts);
      case 'onAlertCancelled':
        _onCancelAlert?.call();
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _onFallDetected = null;
    _onCancelAlert = null;
  }
}
