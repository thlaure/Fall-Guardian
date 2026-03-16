import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Thresholds sent to watch via shared prefs (watch reads them)
  double _freeFallThreshold = 0.5; // g
  double _impactThreshold = 2.5;   // g
  double _tiltThreshold = 45.0;    // degrees
  int _freeFallMinMs = 80;          // ms
  bool _loading = true;

  static const _kFreeFall = 'thresh_freefall';
  static const _kImpact = 'thresh_impact';
  static const _kTilt = 'thresh_tilt';
  static const _kFreeFallMs = 'thresh_freefall_ms';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _freeFallThreshold = prefs.getDouble(_kFreeFall) ?? 0.5;
      _impactThreshold = prefs.getDouble(_kImpact) ?? 2.5;
      _tiltThreshold = prefs.getDouble(_kTilt) ?? 45.0;
      _freeFallMinMs = prefs.getInt(_kFreeFallMs) ?? 80;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFreeFall, _freeFallThreshold);
    await prefs.setDouble(_kImpact, _impactThreshold);
    await prefs.setDouble(_kTilt, _tiltThreshold);
    await prefs.setInt(_kFreeFallMs, _freeFallMinMs);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionHeader('PSP Fall Detection Thresholds'),
                const SizedBox(height: 8),
                _infoCard(
                  'These thresholds control sensitivity. Lower free-fall '
                  'and higher impact thresholds reduce false positives. '
                  'PSP falls often lack a free-fall phase — impact + tilt '
                  'alone will trigger an alert.',
                ),
                const SizedBox(height: 24),
                _sliderTile(
                  label: 'Free-fall threshold',
                  value: _freeFallThreshold,
                  unit: 'g',
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  description:
                      '‖accel‖ must drop below this to detect free-fall phase',
                  onChanged: (v) => setState(() => _freeFallThreshold = v),
                ),
                _sliderTile(
                  label: 'Impact threshold',
                  value: _impactThreshold,
                  unit: 'g',
                  min: 1.5,
                  max: 5.0,
                  divisions: 35,
                  description:
                      '‖accel‖ spike must exceed this to detect impact',
                  onChanged: (v) => setState(() => _impactThreshold = v),
                ),
                _sliderTile(
                  label: 'Tilt threshold',
                  value: _tiltThreshold,
                  unit: '°',
                  min: 20.0,
                  max: 90.0,
                  divisions: 70,
                  description:
                      'Angle from upright must exceed this after impact',
                  onChanged: (v) => setState(() => _tiltThreshold = v),
                ),
                _sliderTile(
                  label: 'Min free-fall duration',
                  value: _freeFallMinMs.toDouble(),
                  unit: 'ms',
                  min: 40,
                  max: 200,
                  divisions: 32,
                  description: 'Minimum duration of free-fall phase',
                  onChanged: (v) =>
                      setState(() => _freeFallMinMs = v.round()),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _freeFallThreshold = 0.5;
                      _impactThreshold = 2.5;
                      _tiltThreshold = 45.0;
                      _freeFallMinMs = 80;
                    });
                    await _save();
                  },
                  icon: const Icon(Icons.restore, color: Colors.white70),
                  label: const Text('Reset to defaults',
                      style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24)),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      );

  Widget _infoCard(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F3460),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
      );

  Widget _sliderTile({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    required int divisions,
    required String description,
    required ValueChanged<double> onChanged,
  }) {
    final displayVal = unit == 'ms'
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
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              Text(displayVal,
                  style: const TextStyle(
                      color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(description,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: const Color(0xFF533483),
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
