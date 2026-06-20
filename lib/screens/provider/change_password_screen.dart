import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Change Password'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.paddingLg,
          children: [
            Text('Choose a strong password you can remember.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(controller: _currentCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 12),
            TextField(controller: _newCtrl, obscureText: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'New password')),
            const SizedBox(height: 12),
            TextField(controller: _confirmCtrl, obscureText: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Confirm new password')),
            const SizedBox(height: 10),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Text(_error!, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting
                    ? null
                    : () async {
                        final newPass = _newCtrl.text.trim();
                        if (newPass.length < 8) {
                          setState(() => _error = 'Password must be at least 8 characters.');
                          return;
                        }
                        if (_confirmCtrl.text.trim() != newPass) {
                          setState(() => _error = 'New passwords do not match.');
                          return;
                        }

                        setState(() {
                          _error = null;
                          _submitting = true;
                        });

                        try {
                          final ok = await auth.changePassword(_currentCtrl.text, newPass);
                          if (!context.mounted) return;
                          if (!ok) {
                            setState(() => _error = 'Password update failed.');
                            return;
                          }
                          context.pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
                        } finally {
                          if (mounted) setState(() => _submitting = false);
                        }
                      },
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
