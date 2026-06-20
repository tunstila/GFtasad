import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:provider/provider.dart';

enum AppAccountMenuAction { signOut }

/// A consistent overflow menu that exposes a production-safe "Sign out" action.
///
/// Add this to any `AppBar.actions` to ensure users can always sign out.
class AppAccountMenu extends StatelessWidget {
  final String? tooltip;

  const AppAccountMenu({super.key, this.tooltip});

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sign out', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'You\'ll need to sign in again to continue.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.pop(true),
                        icon: Icon(Icons.logout, color: scheme.onPrimary),
                        label: Text('Sign out', style: TextStyle(color: scheme.onPrimary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await context.read<AuthService>().logout();
    } catch (e) {
      debugPrint('Logout failed: $e');
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppAccountMenuAction>(
      tooltip: tooltip ?? 'Account',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case AppAccountMenuAction.signOut:
            _confirmAndSignOut(context);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: AppAccountMenuAction.signOut,
          child: Row(
            children: [
              Icon(Icons.logout),
              SizedBox(width: 10),
              Text('Sign out'),
            ],
          ),
        ),
      ],
    );
  }
}
