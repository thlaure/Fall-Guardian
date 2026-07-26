import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/companion_enrollment_service.dart';
import '../services/watch_communication_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.enrollmentCoordinator,
    this.platformOverride,
  });

  final CompanionEnrollmentCoordinator enrollmentCoordinator;
  final CompanionPlatform? platformOverride;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _freeFallThreshold = 0.7;
  double _impactThreshold = 2.5;
  double _tiltThreshold = 50.0;
  int _freeFallMinMs = 60;
  bool _loading = true;
  _EnrollmentState _enrollmentState = _EnrollmentState.idle;
  DateTime? _enrollmentExpiresAt;
  Timer? _enrollmentExpiryTimer;

  /// Machine-readable cause reported by the native watch bridge, used to show
  /// the wearer what to actually do about it. Never contains the token.
  String? _enrollmentFailureReason;

  static const _kFreeFall = 'thresh_freefall';
  static const _kImpact = 'thresh_impact';
  static const _kTilt = 'thresh_tilt';
  static const _kFreeFallMs = 'thresh_freefall_ms';
  static const _kAlgorithmVersion = 'fall_algorithm_version';
  static const _algorithmVersion = 2;

  CompanionPlatform get _companionPlatform =>
      widget.platformOverride ??
      (Platform.isIOS ? CompanionPlatform.watchOS : CompanionPlatform.wearOS);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt(_kAlgorithmVersion) ?? 1) < _algorithmVersion) {
      // Rebase only untouched legacy defaults. User-tuned values remain intact.
      if (prefs.getDouble(_kFreeFall) == 0.5) {
        await prefs.setDouble(_kFreeFall, 0.7);
      }
      if (prefs.getDouble(_kTilt) == 45.0) {
        await prefs.setDouble(_kTilt, 50.0);
      }
      if (prefs.getInt(_kFreeFallMs) == 80) {
        await prefs.setInt(_kFreeFallMs, 60);
      }
      await prefs.setInt(_kAlgorithmVersion, _algorithmVersion);
    }
    setState(() {
      _freeFallThreshold = prefs.getDouble(_kFreeFall) ?? 0.7;
      _impactThreshold = prefs.getDouble(_kImpact) ?? 2.5;
      _tiltThreshold = prefs.getDouble(_kTilt) ?? 50.0;
      _freeFallMinMs = prefs.getInt(_kFreeFallMs) ?? 60;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFreeFall, _freeFallThreshold);
    await prefs.setDouble(_kImpact, _impactThreshold);
    await prefs.setDouble(_kTilt, _tiltThreshold);
    await prefs.setInt(_kFreeFallMs, _freeFallMinMs);
    // Push updated thresholds to connected watch(es) — fire-and-forget
    unawaited(
      WatchCommunicationService.pushThresholds(
        freeFall: _freeFallThreshold,
        impact: _impactThreshold,
        tilt: _tiltThreshold,
        freeFallMs: _freeFallMinMs,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }

  Future<void> _connectWatch() async {
    _enrollmentExpiryTimer?.cancel();
    setState(() {
      _enrollmentState = _EnrollmentState.sending;
      _enrollmentExpiresAt = null;
      _enrollmentFailureReason = null;
    });

    try {
      final enrollment = await widget.enrollmentCoordinator.start(
        _companionPlatform,
      );
      if (!mounted) return;
      setState(() {
        _enrollmentState = _EnrollmentState.waitingForWatch;
        _enrollmentExpiresAt = enrollment.expiresAt;
      });
      final remaining = enrollment.expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _markEnrollmentExpired();
      } else {
        _enrollmentExpiryTimer = Timer(remaining, _markEnrollmentExpired);
      }
    } catch (error, stackTrace) {
      // Watch pairing is a safety-critical setup step. Swallowing the cause
      // makes a failed pairing impossible to diagnose from a bug report, so
      // log it; the native side reports which precondition failed (for
      // example `watch_app_not_installed`) without exposing the token.
      developer.log(
        'companion enrollment failed',
        name: 'SettingsScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _enrollmentState = _EnrollmentState.failed;
        _enrollmentFailureReason =
            error is PlatformException && error.details is String
                ? error.details as String
                : null;
      });
    }
  }

  /// Maps the native bridge's failure cause to advice the wearer can act on.
  /// An unrecognised or absent cause falls back to the generic message so a
  /// new native reason can never leave the card blank.
  String _enrollmentFailureMessage(AppLocalizations l10n) =>
      switch (_enrollmentFailureReason) {
        'watch_app_not_installed' => l10n.watchConnectionAppMissing,
        'watch_not_paired' => l10n.watchConnectionNotPaired,
        'session_not_activated' => l10n.watchConnectionNotReady,
        _ => l10n.watchConnectionFailed,
      };

  void _markEnrollmentExpired() {
    if (!mounted || _enrollmentState != _EnrollmentState.waitingForWatch) {
      return;
    }
    setState(() {
      _enrollmentState = _EnrollmentState.expired;
      _enrollmentExpiresAt = null;
    });
  }

  @override
  void dispose() {
    _enrollmentExpiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        actions: [TextButton(onPressed: _save, child: Text(l10n.save))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionHeader(l10n.watchConnectionSection, cs),
                const SizedBox(height: 8),
                _watchConnectionCard(l10n, cs),
                const SizedBox(height: 32),
                _sectionHeader(l10n.thresholdsSection, cs),
                const SizedBox(height: 8),
                _infoCard(l10n.thresholdsInfo, cs),
                const SizedBox(height: 24),
                _sliderTile(
                  label: l10n.freeFallLabel,
                  value: _freeFallThreshold,
                  unit: l10n.unitG,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  description: l10n.freeFallDesc,
                  onChanged: (v) => setState(() => _freeFallThreshold = v),
                  cs: cs,
                ),
                _sliderTile(
                  label: l10n.impactLabel,
                  value: _impactThreshold,
                  unit: l10n.unitG,
                  min: 1.5,
                  max: 5.0,
                  divisions: 35,
                  description: l10n.impactDesc,
                  onChanged: (v) => setState(() => _impactThreshold = v),
                  cs: cs,
                ),
                _sliderTile(
                  label: l10n.tiltLabel,
                  value: _tiltThreshold,
                  unit: l10n.unitDeg,
                  min: 20.0,
                  max: 90.0,
                  divisions: 70,
                  description: l10n.tiltDesc,
                  onChanged: (v) => setState(() => _tiltThreshold = v),
                  cs: cs,
                ),
                _sliderTile(
                  label: l10n.freeFallDurationLabel,
                  value: _freeFallMinMs.toDouble(),
                  unit: l10n.unitMs,
                  min: 40,
                  max: 200,
                  divisions: 32,
                  description: l10n.freeFallDurationDesc,
                  onChanged: (v) => setState(() => _freeFallMinMs = v.round()),
                  cs: cs,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _freeFallThreshold = 0.7;
                      _impactThreshold = 2.5;
                      _tiltThreshold = 50.0;
                      _freeFallMinMs = 60;
                    });
                    await _save();
                  },
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.resetDefaults),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, ColorScheme cs) => Text(
        title,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _infoCard(String text, ColorScheme cs) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );

  Widget _watchConnectionCard(AppLocalizations l10n, ColorScheme cs) {
    final sending = _enrollmentState == _EnrollmentState.sending;
    final waiting = _enrollmentState == _EnrollmentState.waitingForWatch;
    final failed = _enrollmentState == _EnrollmentState.failed;
    final retryable = failed || _enrollmentState == _EnrollmentState.expired;
    final status = switch (_enrollmentState) {
      _EnrollmentState.idle => l10n.watchNotConnected,
      _EnrollmentState.sending => l10n.watchConnectionStarting,
      _EnrollmentState.waitingForWatch => l10n.watchConnectionWaiting,
      _EnrollmentState.failed => _enrollmentFailureMessage(l10n),
      _EnrollmentState.expired => l10n.watchConnectionExpired,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  waiting ? Icons.watch_outlined : Icons.watch_off_outlined,
                  color: failed ? cs.error : cs.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(status)),
                if (sending)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_enrollmentExpiresAt != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.watchConnectionExpires(
                  _enrollmentExpiresAt!.toLocal(),
                ),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sending ? null : _connectWatch,
              icon: const Icon(Icons.link),
              label: Text(
                retryable ? l10n.retryWatchConnection : l10n.connectWatch,
                // Expired and delivery-failed states both restart safely with
                // a new one-time token.
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderTile({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    required int divisions,
    required String description,
    required ValueChanged<double> onChanged,
    required ColorScheme cs,
  }) {
    final displayVal = unit == AppLocalizations.of(context).unitMs
        ? '${value.round()}$unit'
        : '${value.toStringAsFixed(1)}$unit';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                displayVal,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            description,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

enum _EnrollmentState {
  idle,
  sending,
  waitingForWatch,
  failed,
  expired,
}
