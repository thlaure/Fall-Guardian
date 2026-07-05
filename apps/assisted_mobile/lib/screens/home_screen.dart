import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/backend_api_service.dart';
import 'contacts_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onSimulateFall, this.backendApi});

  final Future<void> Function(int timestamp)? onSimulateFall;
  final BackendApiService? backendApi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BackendApiService _backendApi =
      widget.backendApi ?? BackendApiService();
  int? _caregiverCount;

  @override
  void initState() {
    super.initState();
    _loadCaregiverCount();
  }

  Future<void> _loadCaregiverCount() async {
    try {
      final caregivers = await _backendApi.getLinkedCaregivers();
      if (!mounted) return;
      setState(() => _caregiverCount = caregivers.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _caregiverCount = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.appTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _StatusCard(l10n: l10n, linked: (_caregiverCount ?? 0) > 0),
            const SizedBox(height: 32),
            _NavButton(
              icon: Icons.people,
              label: l10n.homeContactsTitle,
              subtitle: _caregiverCount == null
                  ? null
                  : l10n.homeCaregiverCount(_caregiverCount!),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ContactsScreen(),
                  ),
                );
                await _loadCaregiverCount();
              },
            ),
            const SizedBox(height: 16),
            _NavButton(
              icon: Icons.history,
              label: l10n.homeHistoryTitle,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
              ),
            ),
            const SizedBox(height: 24),
            if (kDebugMode && widget.onSimulateFall != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  onPressed: () => widget.onSimulateFall!(
                    DateTime.now().millisecondsSinceEpoch,
                  ),
                  icon: const Icon(Icons.bug_report, color: Color(0xFFE5694A)),
                  label: const Text(
                    'Simulate Fall (debug)',
                    style: TextStyle(color: Color(0xFFE5694A)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5694A)),
                  ),
                ),
              ),
            Text(
              l10n.homeFootnote,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppLocalizations l10n;
  final bool linked;

  const _StatusCard({required this.l10n, required this.linked});

  @override
  Widget build(BuildContext context) {
    final colors = linked
        ? const [Color(0xFF001A18), Color(0xFF003F3C)]
        : const [Color(0xFF403016), Color(0xFF70531B)];
    final icon = linked ? Icons.shield : Icons.link_off;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
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
            child: Icon(icon, color: Colors.white, size: 36),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linked ? l10n.homeStatusTitle : l10n.homeStatusUnlinkedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  linked ? l10n.homeStatusBody : l10n.homeStatusUnlinkedBody,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
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
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: cs.primary, size: 28),
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
                        fontWeight: FontWeight.w600,
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
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
