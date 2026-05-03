import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/caregiver_backend_service.dart';

/// Screen where the caregiver enters the 8-character invite code generated
/// by the protected-person's device.
class LinkScreen extends StatefulWidget {
  const LinkScreen({super.key, required this.onLinked});

  final VoidCallback onLinked;

  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = CaregiverBackendService();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _api.acceptInvite(_codeController.text.trim().toUpperCase());
      if (mounted) widget.onLinked();
    } on CaregiverApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.statusCode == 404
            ? l10n.codeNotFound
            : l10n.inviteFailed(e.statusCode ?? 0);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.connectionError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.linkScreenTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF183153), Color(0xFF284B63)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(Icons.link, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    l10n.enterInviteCodeTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.inviteCodeInstructions,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: l10n.codeFieldLabel,
                  prefixIcon: const Icon(Icons.vpn_key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                ),
                validator: (v) {
                  if (v == null || v.trim().length != 8) {
                    return l10n.codeFieldValidation;
                  }
                  return null;
                },
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _accept,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(l10n.linkAsCaregiverButton),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
