import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/fall_event.dart';
import '../repositories/fall_events_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repo = FallEventsRepository();
  List<FallEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await _repo.getAll();
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear history?'),
        content:
            const Text('This will permanently delete all fall event records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title:
            const Text('Fall History', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_events.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white70),
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 72, color: Colors.white24),
                      SizedBox(height: 16),
                      Text('No fall events recorded',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (_, i) => _EventTile(event: _events[i]),
                ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final FallEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy — h:mm a');
    final (icon, color, label) = switch (event.status) {
      FallEventStatus.alertSent => (Icons.send, Colors.redAccent, 'Alert Sent'),
      FallEventStatus.alertFailed => (Icons.sms_failed, Colors.deepOrange, 'SMS Failed'),
      FallEventStatus.cancelled => (Icons.cancel, Colors.greenAccent, 'Cancelled'),
      FallEventStatus.timedOutNoSms => (
          Icons.timer_off,
          Colors.orangeAccent,
          'Timed Out'
        ),
    };

    return Card(
      color: const Color(0xFF0F3460),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(fmt.format(event.timestamp.toLocal()),
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12)),
              ],
            ),
            if (event.notifiedContacts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Notified: ${event.notifiedContacts.join(', ')}',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
            if (event.latitude != null && event.longitude != null) ...[
              const SizedBox(height: 4),
              Text(
                  'Location: ${event.latitude!.toStringAsFixed(5)}, '
                  '${event.longitude!.toStringAsFixed(5)}',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
