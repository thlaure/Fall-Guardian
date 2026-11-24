import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../services/alert_actions.dart';
import '../services/caregiver_backend_service.dart';
import '../services/fall_alert_details.dart';
import '../utils/relative_time.dart';

const _alertRed = Color(0xFFB00020);

/// Full-screen alert shown when a fall notification is received.
class ActiveAlertScreen extends StatefulWidget {
  const ActiveAlertScreen({
    super.key,
    required this.alertData,
    required this.onDismiss,
    this.liveAlert,
    this.backend,
    this.actions,
    this.clock,
    this.deviceLocale,
    this.waitingCount = 0,
  });

  /// Data payload from the FCM message or from active alert recovery.
  /// See [FallAlertDetails] for the accepted keys.
  final Map<String, dynamic> alertData;

  /// Newer data for the same alert (reminder push, handling state from
  /// polling). Takes precedence over [alertData] when provided.
  final ValueListenable<Map<String, dynamic>>? liveAlert;

  final VoidCallback onDismiss;
  final CaregiverBackendService? backend;
  final AlertActions? actions;
  final DateTime Function()? clock;

  /// Phone region used to pick the emergency number. Defaults to the device
  /// locale (the app locale has no country because only languages are
  /// supported).
  final Locale? deviceLocale;

  /// Other alerts queued behind this one.
  final int waitingCount;

  @override
  State<ActiveAlertScreen> createState() => _ActiveAlertScreenState();
}

class _ActiveAlertScreenState extends State<ActiveAlertScreen> {
  late final CaregiverBackendService _api =
      widget.backend ?? CaregiverBackendService();
  late final AlertActions _actions =
      widget.actions ?? const UrlLauncherAlertActions();
  Timer? _relativeTimeTicker;
  bool _acknowledging = false;

  Map<String, dynamic> get _data => widget.liveAlert?.value ?? widget.alertData;
  FallAlertDetails get _alert => FallAlertDetails.fromData(_data);
  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.liveAlert?.addListener(_onLiveAlertChanged);
    // Keeps "x min ago" accurate while the screen stays open.
    _relativeTimeTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void didUpdateWidget(covariant ActiveAlertScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveAlert != widget.liveAlert) {
      oldWidget.liveAlert?.removeListener(_onLiveAlertChanged);
      widget.liveAlert?.addListener(_onLiveAlertChanged);
    }
  }

  @override
  void dispose() {
    widget.liveAlert?.removeListener(_onLiveAlertChanged);
    _relativeTimeTicker?.cancel();
    super.dispose();
  }

  void _onLiveAlertChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _acknowledge() async {
    final alertId = _alert.alertId;
    setState(() => _acknowledging = true);
    try {
      if (alertId.isEmpty) {
        throw StateError('Cannot acknowledge alert without alertId');
      }
      await _api.acknowledgeFallAlert(alertId);
      if (mounted) widget.onDismiss();
    } catch (e) {
      developer.log(
        'Failed to acknowledge alert: $e',
        name: '_ActiveAlertScreenState',
      );
      if (mounted) {
        setState(() => _acknowledging = false);
        _showMessage(AppLocalizations.of(context).connectionError);
      }
    }
  }

  Future<void> _openMap(FallAlertDetails alert) async {
    final opened = await _actions.openMap(
      latitude: alert.latitude!,
      longitude: alert.longitude!,
    );
    if (!opened && mounted) {
      _showMessage(AppLocalizations.of(context).mapsUnavailable);
    }
  }

  Future<void> _callEmergency(String number) async {
    final opened = await _actions.call(number);
    if (!opened && mounted) {
      _showMessage(AppLocalizations.of(context).dialerUnavailable);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTime(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  String _detectedLabel(BuildContext context, FallAlertDetails alert) {
    final l10n = AppLocalizations.of(context);
    final detectedAt = alert.fallDetectedAt?.toLocal();
    if (detectedAt == null) {
      return l10n.detectedAt(
        alert.rawFallTimestamp.isEmpty
            ? l10n.unknownDate
            : alert.rawFallTimestamp,
      );
    }
    final date = MaterialLocalizations.of(context).formatMediumDate(detectedAt);
    final relative = relativeTimeLabel(l10n, detectedAt, _now().toLocal());
    return '${l10n.detectedOn(date, _formatTime(context, detectedAt))} · $relative';
  }

  String? _handlingLabel(BuildContext context, FallAlertDetails alert) {
    final l10n = AppLocalizations.of(context);
    return switch (alert.handlingState) {
      AlertHandlingState.none => null,
      AlertHandlingState.handledByMe => l10n.handlingByMe,
      AlertHandlingState.handledByOther =>
        alert.acknowledgedAt == null
            ? l10n.handlingByOther
            : l10n.handlingByOtherSince(
                _formatTime(context, alert.acknowledgedAt!.toLocal()),
              ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final alert = _alert;
    final personName = alert.protectedPersonName ?? l10n.yourContact;
    final handlingLabel = _handlingLabel(context, alert);
    final emergencyNumber = emergencyNumberFor(
      widget.deviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
    );

    return Scaffold(
      backgroundColor: _alertRed,
      body: SafeArea(
        child: Semantics(
          container: true,
          label: l10n.fallAlertSemantics(personName),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (alert.isReminder) ...[
                          _Banner(
                            icon: Icons.notifications_active,
                            text: l10n.reminderBanner,
                            background: const Color(0xFFFFD54F),
                            foreground: Colors.black,
                          ),
                          const SizedBox(height: 16),
                        ],
                        const ExcludeSemantics(
                          child: Icon(
                            Icons.warning_rounded,
                            color: Colors.white,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.fallDetectedTitle,
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.fallDetectedFor(personName),
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _detectedLabel(context, alert),
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (handlingLabel != null) ...[
                          const SizedBox(height: 16),
                          _Banner(
                            icon:
                                alert.handlingState ==
                                    AlertHandlingState.handledByMe
                                ? Icons.check_circle
                                : Icons.people_alt,
                            text: handlingLabel,
                            background: Colors.white,
                            foreground: _alertRed,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          alert.hasLocation
                              ? l10n.activeAlertGuidanceWithLocation
                              : l10n.activeAlertGuidanceWithoutLocation,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (alert.hasLocation) ...[
                          _ActionButton(
                            icon: Icons.directions,
                            label: l10n.openInMaps,
                            onPressed: () => _openMap(alert),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _ActionButton(
                          icon: Icons.local_phone,
                          label: l10n.callEmergencyServices(emergencyNumber),
                          onPressed: () => _callEmergency(emergencyNumber),
                        ),
                        const SizedBox(height: 16),
                        _InfoCard(
                          icon: Icons.health_and_safety_outlined,
                          title: l10n.activeAlertEmergencyTitle,
                          body: l10n.activeAlertEmergencyBody,
                        ),
                        const SizedBox(height: 8),
                        _DetailsSection(alert: alert),
                        if (widget.waitingCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.moreAlertsWaiting(widget.waitingCount),
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _acknowledging ? null : _acknowledge,
                  icon: _acknowledging
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _alertRed,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(l10n.imHandlingIt),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _alertRed,
                    disabledBackgroundColor: Colors.white70,
                    disabledForegroundColor: _alertRed,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (alert.handlingState ==
                    AlertHandlingState.handledByOther) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onDismiss,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(l10n.closeAlert),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        textStyle: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, color: foreground)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Technical information kept out of the main view (only useful for support).
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.alert});

  final FallAlertDetails alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Colors.white);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        title: Text(
          l10n.alertDetailsTitle,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: Colors.white),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '${l10n.alertIdTitle}: ${alert.alertId}',
            style: style,
          ),
          if (alert.hasLocation) ...[
            const SizedBox(height: 4),
            SelectableText(
              l10n.coordinatesLabel(
                alert.latitude!.toStringAsFixed(5),
                alert.longitude!.toStringAsFixed(5),
              ),
              style: style,
            ),
          ],
          const SizedBox(height: 8),
        ],
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
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: Colors.white, size: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
