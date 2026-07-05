import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/caregiver_backend_service.dart';
import 'alert_history_screen.dart';
import 'protected_persons_screen.dart';

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({
    super.key,
    required this.isLinked,
    this.onLinked,
    this.backend,
  });

  final bool isLinked;
  final VoidCallback? onLinked;
  final CaregiverBackendService? backend;

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  late final CaregiverBackendService _backend =
      widget.backend ?? CaregiverBackendService();
  late bool _linked;
  int? _protectedPersonsCount;

  @override
  void initState() {
    super.initState();
    _linked = widget.isLinked;
    _loadProtectedPersonsCount();
  }

  @override
  void didUpdateWidget(covariant CaregiverHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLinked != widget.isLinked) {
      _linked = widget.isLinked;
    }
  }

  Future<void> _loadProtectedPersonsCount() async {
    try {
      final persons = await _backend.getLinkedProtectedPersons();
      if (!mounted) return;
      setState(() => _protectedPersonsCount = persons.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _protectedPersonsCount = null);
    }
  }

  void _onLinked() {
    setState(() => _linked = true);
    widget.onLinked?.call();
    _loadProtectedPersonsCount();
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.linkedSnackbar)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.health_and_safety_outlined, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.appTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CaregiverHero(l10n: l10n, linked: _linked),
            const SizedBox(height: 24),
            _NavButton(
              icon: Icons.people_alt_outlined,
              label: l10n.protectedPersonsButton,
              subtitle: _protectedPersonsCount == null
                  ? null
                  : l10n.protectedPersonsCount(_protectedPersonsCount!),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProtectedPersonsScreen(onLinked: _onLinked),
                  ),
                );
                await _loadProtectedPersonsCount();
              },
            ),
            const SizedBox(height: 16),
            _NavButton(
              icon: Icons.history,
              label: l10n.historyTitle,
              onTap: _linked
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AlertHistoryScreen(),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaregiverHero extends StatelessWidget {
  const _CaregiverHero({required this.l10n, required this.linked});

  final AppLocalizations l10n;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3D35), Color(0xFF2D6A4F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(
              linked ? Icons.volunteer_activism : Icons.link_off,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linked ? l10n.statusLinkedTitle : l10n.statusUnlinkedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  linked ? l10n.statusLinkedBody : l10n.howItWorksBody,
                  style: TextStyle(
                    color: cs.onPrimary.withValues(alpha: 0.82),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Material(
      color: enabled ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled ? cs.primary : cs.onSurfaceVariant,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? cs.onSurfaceVariant : cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
