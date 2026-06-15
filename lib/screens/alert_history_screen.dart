import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../services/caregiver_backend_service.dart';

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
    final da = DateTime.tryParse('${a['fallDetectedAt']}');
    final db = DateTime.tryParse('${b['fallDetectedAt']}');
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall History'),
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
                  const Text('Failed to load history'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
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
                    'No fall alerts yet',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 18),
                  ),
                ],
              ),
            )
          : _buildGroupedList(cs),
    );
  }

  Widget _buildGroupedList(ColorScheme cs) {
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) const SizedBox(height: 24),
            _DeviceHeader(
              label: 'Device $deviceNumber',
              platform: platform,
              alertCount: deviceAlerts.length,
              cs: cs,
            ),
            const SizedBox(height: 8),
            ...deviceAlerts.map((alert) => _AlertTile(alert: alert, cs: cs)),
          ],
        );
      },
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({
    required this.label,
    required this.platform,
    required this.alertCount,
    required this.cs,
  });

  final String label;
  final String platform;
  final int alertCount;
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
        Text(
          '$label (${platform.toUpperCase()})',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$alertCount',
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
  const _AlertTile({required this.alert, required this.cs});

  final Map<String, dynamic> alert;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final status = '${alert['status'] ?? ''}';
    final acknowledged = alert['acknowledged'] == true;
    final isCancelled = status == 'cancelled';

    final date = DateTime.tryParse(
      '${alert['fallDetectedAt'] ?? ''}',
    )?.toLocal();
    final dateStr = date != null
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : 'Unknown date';

    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    if (isCancelled) {
      statusColor = cs.onSurfaceVariant;
      statusIcon = Icons.cancel_outlined;
      statusLabel = 'Stopped by protected person';
    } else if (acknowledged) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
      statusLabel = 'Acknowledged';
    } else {
      statusColor = cs.error;
      statusIcon = Icons.warning_amber_rounded;
      statusLabel = 'Unacknowledged';
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
