import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/contact.dart';
import '../models/fall_event.dart';
import '../repositories/contacts_repository.dart';
import '../repositories/fall_events_repository.dart';
import '../services/location_service.dart';
import '../services/sms_service.dart';
import '../services/notification_service.dart';
import 'package:uuid/uuid.dart';

class FallAlertScreen extends StatefulWidget {
  final int fallTimestamp;

  const FallAlertScreen({super.key, required this.fallTimestamp});

  @override
  State<FallAlertScreen> createState() => _FallAlertScreenState();
}

class _FallAlertScreenState extends State<FallAlertScreen>
    with TickerProviderStateMixin {
  static const _countdownSeconds = 30;

  int _remaining = _countdownSeconds;
  Timer? _timer;
  bool _dismissed = false;
  bool _sending = false;
  String _statusMessage = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupPulse();
    _startCountdown();
  }

  void _setupPulse() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.9, end: 1.1).animate(_pulseController);
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        _sendAlert();
      }
    });
  }

  Future<void> _sendAlert() async {
    if (_dismissed || _sending) return;
    setState(() {
      _sending = true;
      _statusMessage = 'Getting your location...';
    });

    final locationService = LocationService();
    final Position? position = await locationService.getCurrentPosition();

    setState(() => _statusMessage = 'Sending SMS alerts...');

    final contacts = await ContactsRepository().getAll();
    final notified = await SmsService().sendFallAlert(
      contacts: contacts,
      latitude: position?.latitude,
      longitude: position?.longitude,
    );

    final smsFailed = contacts.isNotEmpty && notified.isEmpty;
    final event = FallEvent(
      id: const Uuid().v4(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(widget.fallTimestamp),
      status: smsFailed ? FallEventStatus.alertFailed : FallEventStatus.alertSent,
      latitude: position?.latitude,
      longitude: position?.longitude,
      notifiedContacts: notified,
    );
    await FallEventsRepository().add(event);

    await NotificationService().cancelAll();

    setState(() => _statusMessage = smsFailed
        ? '⚠️ SMS failed to send. Call your contacts manually!'
        : 'Alert sent to ${notified.length} contact(s).');

    await Future.delayed(const Duration(seconds: smsFailed ? 5 : 2));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    setState(() => _dismissed = true);

    final event = FallEvent(
      id: const Uuid().v4(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(widget.fallTimestamp),
      status: FallEventStatus.cancelled,
    );
    await FallEventsRepository().add(event);
    await NotificationService().cancelAll();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remaining / _countdownSeconds;

    return WillPopScope(
      onWillPop: () async => false, // prevent back button dismiss
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 80,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Fall Detected!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your emergency contacts will be notified unless you cancel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),
                _sending
                    ? Column(
                        children: [
                          const CircularProgressIndicator(
                              color: Colors.redAccent),
                          const SizedBox(height: 16),
                          Text(_statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14)),
                        ],
                      )
                    : Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 8,
                                  backgroundColor: Colors.white12,
                                  color: _remaining <= 10
                                      ? Colors.redAccent
                                      : Colors.orangeAccent,
                                ),
                              ),
                              Text(
                                '$_remaining',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 48),
                          SizedBox(
                            height: 60,
                            child: ElevatedButton.icon(
                              onPressed: _cancel,
                              icon: const Icon(Icons.check_circle, size: 28),
                              label: const Text("I'm OK — Cancel Alert",
                                  style: TextStyle(fontSize: 18)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
