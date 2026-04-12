import 'package:flutter/material.dart';
import 'link_screen.dart';

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({
    super.key,
    required this.isLinked,
    this.onLinked,
  });

  final bool isLinked;
  final VoidCallback? onLinked;

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  late bool _linked;

  @override
  void initState() {
    super.initState();
    _linked = widget.isLinked;
  }

  void _onLinked() {
    setState(() => _linked = true);
    widget.onLinked?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Linked successfully! You will now receive fall alerts.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fall Guardian Caregiver',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _linked
                      ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                      : [const Color(0xFF183153), const Color(0xFF284B63)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    _linked ? Icons.volunteer_activism : Icons.link_off,
                    color: Colors.white,
                    size: 54,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _linked ? 'Monitoring Active' : 'Not Linked Yet',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _linked
                        ? 'You will receive push alerts if a fall is detected on the protected person\'s device.'
                        : 'Link with a protected person to start receiving fall alerts.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (!_linked) ...[
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LinkScreen(onLinked: _onLinked),
                  ),
                ),
                icon: const Icon(Icons.add_link),
                label: const Text('Link with Protected Person'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _InfoCard(
              title: _linked ? 'Status' : 'How it works',
              body: _linked
                  ? 'Push notifications are active. Keep this app installed.'
                  : '1. Ask the protected person to generate a code in their Fall Guardian app.\n'
                      '2. Tap "Link" above and enter the code.\n'
                      '3. You\'ll receive push alerts on every detected fall.',
              icon: _linked ? Icons.check_circle_outline : Icons.info_outline,
            ),
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Important',
              body: 'Keep notifications enabled for this app. Fall alerts are delivered as data-only messages — your phone must be on and connected.',
              icon: Icons.notifications_active_outlined,
            ),
            const SizedBox(height: 24),
            Text(
              'Separate apps keep the protected-person and caregiver flows cleaner, safer, and easier to maintain.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
