import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/caregiver_backend_service.dart';
import 'link_screen.dart';

class ProtectedPersonsScreen extends StatefulWidget {
  const ProtectedPersonsScreen({super.key, this.onLinked, this.backend});

  final VoidCallback? onLinked;
  final CaregiverBackendService? backend;

  @override
  State<ProtectedPersonsScreen> createState() => _ProtectedPersonsScreenState();
}

class _ProtectedPersonsScreenState extends State<ProtectedPersonsScreen> {
  late final CaregiverBackendService _backend =
      widget.backend ?? CaregiverBackendService();

  List<LinkedProtectedPerson> _protectedPersons = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final protectedPersons = await _backend.getLinkedProtectedPersons();
      if (!mounted) return;
      setState(() {
        _protectedPersons = protectedPersons;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Protected persons load error: $e');
      developer.log(
        'Protected persons load error: $e',
        name: 'ProtectedPersonsScreen',
      );
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  void _handleLinked() {
    widget.onLinked?.call();
    _load();
  }

  void _openLinkScreen() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LinkScreen(onLinked: _handleLinked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.protectedPersonsTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: _openLinkScreen,
        tooltip: l10n.linkButton,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (_loadFailed)
                    _LoadFailedState(onRetry: _load)
                  else if (_protectedPersons.isEmpty)
                    const _EmptyProtectedPersonsState()
                  else ...[
                    Text(
                      l10n.protectedPersonsCount(_protectedPersons.length),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._protectedPersons.indexed.map(
                      (entry) => _ProtectedPersonTile(
                        index: entry.$1,
                        protectedPerson: entry.$2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }
}

class _ProtectedPersonTile extends StatelessWidget {
  const _ProtectedPersonTile({
    required this.index,
    required this.protectedPerson,
  });

  final int index;
  final LinkedProtectedPerson protectedPerson;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.person_outline, color: cs.onPrimaryContainer),
        ),
        title: Text(l10n.protectedPersonLabel(index + 1)),
        subtitle: Text(l10n.statusLinkedBody),
        iconColor: cs.primary,
      ),
    );
  }
}

class _EmptyProtectedPersonsState extends StatelessWidget {
  const _EmptyProtectedPersonsState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(
          Icons.people_alt_outlined,
          size: 64,
          color: cs.onSurfaceVariant.withValues(alpha: 0.45),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.protectedPersonsEmptyTitle,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.protectedPersonsEmptyBody,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LoadFailedState extends StatelessWidget {
  const _LoadFailedState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(Icons.cloud_off, size: 48, color: cs.error),
        const SizedBox(height: 12),
        Text(l10n.protectedPersonsLoadFailed),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
      ],
    );
  }
}
