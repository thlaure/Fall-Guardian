import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/caregiver_backend_service.dart';
import '../utils/api_date_time.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  final _backend = CaregiverBackendService();
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final alerts = await _backend.getCaregiverAlerts();
      alerts.sort(_newestFirst);
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _loading = false;
        });
      }
    } catch (e) {
      developer.log('Alert history load error: $e', name: 'AlertHistoryScreen');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int _newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final da = parseApiDateTime('${a['fallDetectedAt']}');
    final db = parseApiDateTime('${b['fallDetectedAt']}');
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  Map<String, List<Map<String, dynamic>>> _groupByDevice() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final alert in _alerts) {
      final deviceId = '${alert['protectedDeviceId'] ?? 'unknown'}';
      groups.putIfAbsent(deviceId, () => []).add(alert);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(l10n.historyLoadFailed),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: Text(l10n.retry)),
                ],
              ),
            )
          : _alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.historyEmpty,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 18),
                  ),
                ],
              ),
            )
          : _buildGroupedList(cs, l10n),
    );
  }

  Widget _buildGroupedList(ColorScheme cs, AppLocalizations l10n) {
    final groups = _groupByDevice();
    final deviceIds = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: deviceIds.length,
      itemBuilder: (context, index) {
        final deviceId = deviceIds[index];
        final deviceAlerts = groups[deviceId]!;
        final platform =
            '${deviceAlerts.first['protectedDevicePlatform'] ?? 'unknown'}';
        final deviceNumber = index + 1;
        final shortDeviceId = deviceId.length <= 8
            ? deviceId
            : deviceId.substring(0, 8);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) const SizedBox(height: 24),
            _DeviceHeader(
              label: l10n.protectedPersonLabel(deviceNumber),
              subtitle: l10n.protectedPersonSubtitle(platform, shortDeviceId),
              platform: platform,
              alertCountLabel: l10n.alertCountLabel(deviceAlerts.length),
              cs: cs,
            ),
            const SizedBox(height: 8),
            ...deviceAlerts.map(
              (alert) => _AlertTile(alert: alert, cs: cs, l10n: l10n),
            ),
          ],
        );
      },
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({
    required this.label,
    required this.subtitle,
    required this.platform,
    required this.alertCountLabel,
    required this.cs,
  });

  final String label;
  final String subtitle;
  final String platform;
  final String alertCountLabel;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          platform == 'ios' ? Icons.phone_iphone : Icons.phone_android,
          size: 18,
          color: cs.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            alertCountLabel,
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.cs, required this.l10n});

  final Map<String, dynamic> alert;
  final ColorScheme cs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final status = '${alert['status'] ?? ''}';
    final acknowledged = alert['acknowledged'] == true;
    final isCancelled = status == 'cancelled';

    final date = parseApiDateTime(
      '${alert['fallDetectedAt'] ?? ''}',
    )?.toLocal();
    final dateStr = date != null
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : l10n.unknownDate;

    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    if (isCancelled) {
      statusColor = cs.onSurfaceVariant;
      statusIcon = Icons.cancel_outlined;
      statusLabel = l10n.statusStoppedByProtectedPerson;
    } else if (acknowledged) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
      statusLabel = l10n.statusAcknowledged;
    } else {
      statusColor = cs.error;
      statusIcon = Icons.warning_amber_rounded;
      statusLabel = l10n.statusUnacknowledged;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          Icons.personal_injury_outlined,
          color: isCancelled ? cs.onSurfaceVariant : cs.error,
        ),
        title: Text(
          dateStr,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 4),
            Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
          ],
        ),
        trailing: alert['latitude'] != null
            ? Icon(Icons.location_on, size: 16, color: cs.primary)
            : null,
      ),
    );
  }
}
