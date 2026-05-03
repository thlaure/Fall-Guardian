import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/caregiver_backend_service.dart';

/// Full-screen alert shown when a fall notification is received.
class ActiveAlertScreen extends StatefulWidget {
  const ActiveAlertScreen({
    super.key,
    required this.alertData,
    required this.onDismiss,
  });

  /// Data payload from the FCM message.
  /// Keys: alertId, fallTimestamp, latitude, longitude.
  final Map<String, dynamic> alertData;
  final VoidCallback onDismiss;

  @override
  State<ActiveAlertScreen> createState() => _ActiveAlertScreenState();
}

class _ActiveAlertScreenState extends State<ActiveAlertScreen> {
  final _api = CaregiverBackendService();
  bool _acknowledging = false;

  String get _alertId => widget.alertData['alertId'] as String? ?? '';
  String get _fallTimestamp =>
      widget.alertData['fallTimestamp'] as String? ?? '';
  String? get _latitude => widget.alertData['latitude'] as String?;
  String? get _longitude => widget.alertData['longitude'] as String?;

  bool get _hasLocation =>
      _latitude != null &&
      _latitude!.isNotEmpty &&
      _longitude != null &&
      _longitude!.isNotEmpty;

  String get _formattedTime {
    final dt = DateTime.tryParse(_fallTimestamp)?.toLocal();
    if (dt == null) return _fallTimestamp;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _acknowledge() async {
    setState(() => _acknowledging = true);
    try {
      if (_alertId.isNotEmpty) {
        await _api.acknowledgeFallAlert(_alertId);
      }
    } catch (e) {
      developer.log(
        'Failed to acknowledge alert: $e',
        name: '_ActiveAlertScreenState',
      );
    }
    if (mounted) widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFB00020),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 96),
              const SizedBox(height: 24),
              Text(
                l10n.fallDetectedTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.detectedAt(_formattedTime),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 32),
              if (_hasLocation) ...[
                _InfoCard(
                  icon: Icons.location_on,
                  title: l10n.locationTitle,
                  body: 'Lat: $_latitude\nLng: $_longitude',
                ),
                const SizedBox(height: 16),
              ],
              _InfoCard(
                icon: Icons.info_outline,
                title: l10n.alertIdTitle,
                body: _alertId,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _acknowledging ? null : _acknowledge,
                icon: _acknowledging
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFB00020),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(l10n.acknowledge),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB00020),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
