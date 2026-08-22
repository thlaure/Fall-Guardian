import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/caregiver_backend_service.dart';
import 'link_screen.dart';

class ProtectedPersonsScreen extends StatefulWidget {
  const ProtectedPersonsScreen({
    super.key,
    this.onLinked,
    this.onLinksChanged,
    this.backend,
  });

  final VoidCallback? onLinked;
  final ValueChanged<bool>? onLinksChanged;
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
  final Set<String> _removingLinkIds = {};

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

  Future<void> _confirmAndRemove(
    LinkedProtectedPerson protectedPerson,
    int index,
  ) async {
    final l10n = AppLocalizations.of(context);
    final name = _protectedPersonName(l10n, protectedPerson, index);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeProtectedPersonTitle(name)),
        content: Text(l10n.removeProtectedPersonBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.removeProtectedPersonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.removeProtectedPersonConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removingLinkIds.add(protectedPerson.linkId));
    try {
      await _backend.removeProtectedPersonLink(protectedPerson.linkId);
      await _load();
      if (!mounted) return;
      widget.onLinksChanged?.call(_protectedPersons.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.removeProtectedPersonSuccess(name))),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Protected person link removal failed',
        name: 'ProtectedPersonsScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.removeProtectedPersonFailed)));
    } finally {
      if (mounted) {
        setState(() => _removingLinkIds.remove(protectedPerson.linkId));
      }
    }
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
                        removing: _removingLinkIds.contains(entry.$2.linkId),
                        onRemove: entry.$2.linkId.isEmpty
                            ? null
                            : () => _confirmAndRemove(entry.$2, entry.$1),
                      ),
                    ),
                  ],
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }

  String _protectedPersonName(
    AppLocalizations l10n,
    LinkedProtectedPerson protectedPerson,
    int index,
  ) => protectedPerson.protectedPersonName?.trim().isNotEmpty == true
      ? protectedPerson.protectedPersonName!.trim()
      : l10n.protectedPersonLabel(index + 1);
}

class _ProtectedPersonTile extends StatelessWidget {
  const _ProtectedPersonTile({
    required this.index,
    required this.protectedPerson,
    required this.removing,
    required this.onRemove,
  });

  final int index;
  final LinkedProtectedPerson protectedPerson;
  final bool removing;
  final VoidCallback? onRemove;

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
        title: Text(
          protectedPerson.protectedPersonName?.trim().isNotEmpty == true
              ? protectedPerson.protectedPersonName!.trim()
              : l10n.protectedPersonLabel(index + 1),
        ),
        subtitle: Text(
          l10n.protectedPersonSubtitle(
            protectedPerson.protectedDevicePlatform,
            _shortDeviceId(protectedPerson.protectedDeviceId),
          ),
        ),
        trailing: removing
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: l10n.removeProtectedPersonTooltip,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
        iconColor: cs.primary,
      ),
    );
  }

  String _shortDeviceId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
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
