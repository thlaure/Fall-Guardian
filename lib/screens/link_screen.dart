import 'package:flutter/material.dart';
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
            ? 'Code not found or expired. Ask for a new code.'
            : 'Failed to accept invite (${e.statusCode}).';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Connection error. Check the backend.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Link with Protected Person')),
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
              child: const Column(
                children: [
                  Icon(Icons.link, color: Colors.white, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Enter Invite Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ask the protected person to generate a code in their Fall Guardian app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
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
                  labelText: '8-character code',
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
                    return 'Enter the full 8-character code';
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
              label: const Text('Link as Caregiver'),
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
