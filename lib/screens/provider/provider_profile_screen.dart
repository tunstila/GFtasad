import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/notification_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/provider_bottom_nav.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class ProviderProfileScreen extends StatelessWidget {
  const ProviderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();
    final notif = context.watch<NotificationService>();

    final user = auth.currentUser;
    final deliveryBadge = (user?.effectiveRole.hasGlobalView ?? false)
        ? deliveryService.getPendingDeliveriesCountAll()
        : deliveryService.getPendingDeliveriesCount(user?.id ?? '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(isLabelVisible: notif.unreadCount > 0, label: Text('${notif.unreadCount}'), child: const Icon(Icons.notifications)),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Expanded(
              child: ListView(
                padding: AppSpacing.paddingLg,
                children: [
                  if (user == null)
                    const Text('No user')
                  else
                    _ProfileHeader(user: user),
                  const SizedBox(height: 18),
                  _SettingsCard(
                    title: 'Account',
                    children: [
                      _SettingsRow(icon: Icons.lock, title: 'Change password', subtitle: 'Update your account password', onTap: () => context.push('/change-password')),
                      _SettingsRow(icon: Icons.sync, title: 'Sync status', subtitle: 'Queued offline records and last sync', onTap: () => context.push('/sync-status')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: 'Business',
                    children: [
                      _SettingsRow(icon: Icons.location_on_outlined, title: 'Business address', subtitle: 'Address, State/LGA, GPS coordinates', onTap: () => context.push('/provider-profile/address')),
                      if (user?.role == UserRole.supplier || user?.hasSuperAdminFull == true)
                        _SettingsRow(icon: Icons.inbox_outlined, title: 'Incoming stock requests', subtitle: 'Requests from field providers', onTap: () => context.push('/supplier/stock-requests')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (user?.effectiveRole.hasGlobalView == true) ...[
                    _SettingsCard(
                      title: 'Administration',
                      children: [
                        _SettingsRow(icon: Icons.admin_panel_settings_outlined, title: 'Users & approvals', subtitle: 'Review pending signups and admin rights', onTap: () => context.push('/admin/users')),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  _SettingsCard(
                    title: 'Notifications',
                    children: [
                      _SettingsRow(icon: Icons.notifications, title: 'Notifications feed', subtitle: 'Low-stock, deliveries, sync alerts', onTap: () => context.push('/notifications')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: 'Session',
                    children: [
                      _SettingsRow(
                        icon: Icons.logout,
                        title: 'Logout',
                        subtitle: 'Sign out of this device',
                        destructive: true,
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Logout?'),
                              content: const Text('You will need to login again to access the app.'),
                              actions: [
                                TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
                                ElevatedButton(onPressed: () => context.pop(true), child: const Text('Logout')),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          await auth.logout();
                          if (!context.mounted) return;
                          context.go('/login');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProviderBottomNav(currentIndex: 4, deliveryBadge: deliveryBadge),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final User user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.username, style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(_subtitle(user), style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (user.role == UserRole.fieldProvider && (user.fieldProviderUniqueId ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30)),
                    ),
                    child: Text(
                      'ID: ${user.fieldProviderUniqueId}',
                      style: context.textStyles.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(User u) {
    final parts = <String>[];
    parts.add(u.role.name);
    if (u.facilityName != null) parts.add(u.facilityName!);
    if (u.lga != null) parts.add(u.lga!);
    if (u.state != null) parts.add(u.state!);
    return parts.join(' • ');
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _SettingsRow({required this.icon, required this.title, required this.subtitle, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = destructive ? scheme.error : scheme.primary;
    final titleColor = destructive ? scheme.error : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: iconColor)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: titleColor)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
