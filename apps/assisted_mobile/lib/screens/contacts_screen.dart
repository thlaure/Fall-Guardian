import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/backend_api_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, this.api});

  final BackendApiService? api;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final BackendApiService _api = widget.api ?? BackendApiService();

  List<Map<String, dynamic>> _linkedCaregivers = [];
  bool _loading = true;
  String? _inviteCode;
  DateTime? _inviteExpiresAt;
  bool _creatingInvite = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final caregivers = await _api.getLinkedCaregivers();
      if (!mounted) return;
      setState(() {
        _linkedCaregivers = caregivers;
        _loading = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load linked caregivers',
        name: 'ContactsScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load caregivers.')),
      );
    }
  }

  Future<void> _revokeCaregiver(String linkId) async {
    try {
      await _api.deleteLinkedCaregiver(linkId);
      await _load();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to create caregiver invite',
        name: 'ContactsScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove caregiver.')),
      );
    }
  }

  Future<void> _createInvite() async {
    setState(() => _creatingInvite = true);
    try {
      final data = await _api.createInvite();
      if (!mounted) return;
      setState(() {
        _inviteCode = data['code'] as String?;
        _inviteExpiresAt = data['expiresAt'] != null
            ? DateTime.tryParse(data['expiresAt'] as String)
            : null;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Failed to create caregiver invite',
        name: 'ContactsScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create invite. Check backend.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _creatingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.contactsScreenTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: _creatingInvite ? null : _createInvite,
        tooltip: 'Generate invite code',
        child: _creatingInvite
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _InviteCaregiverSection(
                    inviteCode: _inviteCode,
                    expiresAt: _inviteExpiresAt,
                  ),
                  const SizedBox(height: 16),
                  if (_linkedCaregivers.isEmpty)
                    _EmptyCaregiversState(l10n: l10n)
                  else
                    _LinkedCaregiversSection(
                      caregivers: _linkedCaregivers,
                      onRevoke: _revokeCaregiver,
                    ),
                ],
              ),
            ),
    );
  }
}

class _InviteCaregiverSection extends StatelessWidget {
  const _InviteCaregiverSection({
    required this.inviteCode,
    required this.expiresAt,
  });

  final String? inviteCode;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final formattedInviteCode = inviteCode == null
        ? null
        : RegExp('.{1,4}').allMatches(inviteCode!).map((m) => m[0]!).join(' ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.link, color: cs.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Invite a caregiver',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            inviteCode == null
                ? 'Tap + to generate a one-time code for a caregiver.'
                : 'Share this code with your caregiver:',
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          ),
          if (formattedInviteCode != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      formattedInviteCode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: cs.primary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy invite code',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inviteCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite code copied.')),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (expiresAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Expires at ${expiresAt!.toLocal().toString().substring(11, 16)}',
                  style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LinkedCaregiversSection extends StatelessWidget {
  const _LinkedCaregiversSection({
    required this.caregivers,
    required this.onRevoke,
  });

  final List<Map<String, dynamic>> caregivers;
  final void Function(String linkId) onRevoke;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${caregivers.length} caregiver${caregivers.length > 1 ? 's' : ''} linked',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        ...caregivers.indexed.map((entry) {
          final caregiver = entry.$2;
          final linkId = caregiver['id'] as String? ?? '';
          final caregiverName = '${caregiver['caregiverName'] ?? ''}'.trim();
          final platform = '${caregiver['platform'] ?? ''}'.trim();
          final deviceId = '${caregiver['caregiverDeviceId'] ?? ''}'.trim();
          final shortDeviceId =
              deviceId.length <= 8 ? deviceId : deviceId.substring(0, 8);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person_outline, color: cs.onPrimaryContainer),
              ),
              title: Text(
                caregiverName.isNotEmpty
                    ? caregiverName
                    : 'Caregiver ${entry.$1 + 1}',
              ),
              subtitle: Text(
                platform.isEmpty
                    ? 'Receives fall alerts from this device'
                    : shortDeviceId.isEmpty
                        ? platform.toUpperCase()
                        : '${platform.toUpperCase()} device $shortDeviceId',
              ),
              trailing: IconButton(
                tooltip: 'Remove caregiver',
                icon: const Icon(Icons.link_off),
                onPressed: linkId.isEmpty ? null : () => onRevoke(linkId),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _EmptyCaregiversState extends StatelessWidget {
  const _EmptyCaregiversState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.contactsEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create an invite code and link a caregiver.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
