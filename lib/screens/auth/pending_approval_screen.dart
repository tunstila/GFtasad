import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/theme.dart';

class PendingApprovalScreen extends StatelessWidget {
  /// mode:
  /// - 'approval' (default): Super Admin approval required
  /// - 'email': user must confirm email before login
  final String? mode;

  const PendingApprovalScreen({super.key, this.mode});

  bool get _isEmailMode => mode == 'email';

  @override
  Widget build(BuildContext context) {
    final title = _isEmailMode ? 'Confirm your email' : 'Approval Required';
    final headline = _isEmailMode ? 'Almost there' : 'Signup request submitted';
    final description = _isEmailMode
        ? 'We sent a confirmation link to your email address. Please confirm your email, then come back and sign in. If you don\'t see the email, check Spam/Junk or try again in a few minutes.'
        : 'A Super Admin must approve your account before you can sign in. After approval, you can sign in with your email and password (you may also receive an approval email if notifications are enabled).';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(title),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              Text(headline, style: context.textStyles.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                description,
                style: context.textStyles.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEmailMode
                            ? 'If you confirmed your email but still cannot sign in, try resetting your password or contact support.'
                            : 'If you believe this is taking too long, contact your state/national administrator.',
                        style: context.textStyles.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login),
                label: const Text('Back to Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
