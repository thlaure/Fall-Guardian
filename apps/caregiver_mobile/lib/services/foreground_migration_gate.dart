import 'dart:developer' as developer;

/// Runs a storage migration only while the app is in the foreground.
///
/// On iOS a fall alert push can launch the whole app in the background while
/// the phone is locked. Keychain items in the legacy class are unreadable
/// then, so migrating would see nothing and could not make progress. The
/// gate skips that launch and runs the migration on the next foreground
/// resume instead. Concurrent callers share one run; a failed or deferred
/// run is retried on the next call.
class ForegroundMigrationGate {
  ForegroundMigrationGate({required this.migrate, required this.isForeground});

  final Future<bool> Function() migrate;
  final bool Function() isForeground;
  Future<bool>? _running;
  bool _completed = false;

  bool get completed => _completed;

  /// Never throws. Returns once the migration finished, was deferred
  /// (background launch) or failed (retried on the next call).
  Future<void> ensure() async {
    if (_completed || !isForeground()) return;

    final running = _running ??= _runSafely();
    final succeeded = await running;
    if (identical(_running, running)) _running = null;
    if (succeeded) _completed = true;
  }

  Future<bool> _runSafely() async {
    try {
      return await migrate();
    } catch (error) {
      developer.log(
        'Keychain migration failed: $error',
        name: 'ForegroundMigrationGate',
      );
      return false;
    }
  }
}
