import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/notification_item.dart';
import 'package:mediflow/services/notification_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notif = context.watch<NotificationService>();
    final unread = notif.unreadItems;
    final read = notif.readItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: unread.isEmpty ? null : () => notif.markAllRead(),
            child: const Text('Mark all read'),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: notif.isLoading
            ? const Center(child: CircularProgressIndicator())
            : (unread.isEmpty && read.isEmpty)
                ? const _EmptyNotificationsState(unreadOnly: false)
                : ListView(
                    padding: AppSpacing.paddingLg,
                    children: [
                      if (unread.isEmpty) const _EmptyNotificationsState(unreadOnly: true) else ...[
                        Text('Unread', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ..._buildCards(context, unread, notif),
                      ],
                      if (read.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('History', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ..._buildCards(context, read, notif),
                      ],
                    ],
                  ),
      ),
    );
  }

  List<Widget> _buildCards(BuildContext context, List<NotificationItem> items, NotificationService notif) {
    return items
        .map((n) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NotificationCard(
                item: n,
                onOpen: () async {
                  await notif.markRead(n.id);
                  if (!context.mounted) return;
                  showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    useSafeArea: true,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    builder: (_) => _NotificationDetailSheet(item: n),
                  );
                },
              ),
            ))
        .toList();
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onOpen;

  const _NotificationCard({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.type) {
      NotificationType.deliveryArrived => (Icons.local_shipping_outlined, AlertColors.info),
      NotificationType.syncFailure => (Icons.cloud_off, AlertColors.critical),
      NotificationType.system => (Icons.info_outline, AlertColors.info),
      NotificationType.lowStock => (Icons.warning_amber, AlertColors.warning),
    };

    final isUnread = item.readState == NotificationReadState.unread;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isUnread ? color.withValues(alpha: 0.38) : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.title, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                      const SizedBox(width: 10),
                      if (isUnread) Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item.description, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(_formatDateTime(item.createdAt), style: context.textStyles.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }
}

class _NotificationDetailSheet extends StatelessWidget {
  final NotificationItem item;

  const _NotificationDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (item.type) {
      NotificationType.syncFailure => AlertColors.critical,
      NotificationType.deliveryArrived || NotificationType.system => AlertColors.info,
      NotificationType.lowStock => AlertColors.warning,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Text(item.description, style: context.textStyles.bodyMedium?.copyWith(height: 1.45, color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 14),
          Text('Received: ${_formatDateTime(item.createdAt)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (item.readAt != null) ...[
            const SizedBox(height: 6),
            Text('Read: ${_formatDateTime(item.readAt!)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  final bool unreadOnly;

  const _EmptyNotificationsState({required this.unreadOnly});

  @override
  Widget build(BuildContext context) {
    final title = unreadOnly ? 'No unread notifications' : 'No notifications yet';
    final subtitle = unreadOnly ? 'You\'re all caught up.' : 'System messages, deliveries, and sync alerts will appear here.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AlertColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.notifications_none, color: AlertColors.info),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
