import 'package:flutter/foundation.dart';

/// App-wide "this phone must be re-paired" signal.
///
/// Several [BackendApiService] instances exist (app root, coordinator,
/// screens); they all report into one shared notifier so the home screen can
/// show a persistent warning the moment any call learns the backend rejected
/// this phone's credentials. The durable source of truth is the
/// `backend_reauth_required` secure-store flag (also written by the native
/// relays); this notifier only mirrors it for the UI.
class DevicePairingState {
  DevicePairingState();

  static final DevicePairingState shared = DevicePairingState();

  final ValueNotifier<bool> repairRequired = ValueNotifier<bool>(false);
}
