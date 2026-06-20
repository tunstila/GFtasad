import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/stock_alert.dart';
import 'package:mediflow/services/stock_alert_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class StockAlertsScreen extends StatelessWidget {
  const StockAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<StockAlertService>();
    final unread = svc.unreadActive;
    final history = svc.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Alerts'),
        actions: [
          TextButton(
            onPressed: svc.unreadActiveCount == 0 ? null : () => svc.markAllRead(),
            child: const Text('Mark all read'),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: svc.isLoading
            ? const Center(child: CircularProgressIndicator())
            : (unread.isEmpty && history.isEmpty)
                ? const _EmptyAlertsState(mode: _EmptyMode.none)
                : ListView(
                    padding: AppSpacing.paddingLg,
                    children: [
                      if (unread.isEmpty) const _EmptyAlertsState(mode: _EmptyMode.unread) else ...[
                        Text('Unread', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ...unread.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _StockAlertCard(
                                alert: a,
                                onOpen: () async {
                                  await svc.markRead(a.id);
                                  if (!context.mounted) return;
                                  showModalBottomSheet(
                                    context: context,
                                    showDragHandle: true,
                                    useSafeArea: true,
                                    backgroundColor: Theme.of(context).colorScheme.surface,
                                    builder: (_) => _StockAlertDetailSheet(alert: a),
                                  );
                                },
                              ),
                            )),
                      ],
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('History', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ...history.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _StockAlertCard(
                                alert: a,
                                onOpen: () {
                                  showModalBottomSheet(
                                    context: context,
                                    showDragHandle: true,
                                    useSafeArea: true,
                                    backgroundColor: Theme.of(context).colorScheme.surface,
                                    builder: (_) => _StockAlertDetailSheet(alert: a),
                                  );
                                },
                              ),
                            )),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _StockAlertCard extends StatelessWidget {
  final StockAlert alert;
  final VoidCallback onOpen;

  const _StockAlertCard({required this.alert, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final isUnread = alert.readState == StockAlertReadState.unread;
    final title = (alert.commodityName ?? alert.title).trim().isEmpty ? alert.title : (alert.commodityName ?? alert.title);

    final icon = switch (alert.type) {
      StockAlertType.outOfStock => Icons.error_outline,
      StockAlertType.nearExpiry => Icons.schedule,
      StockAlertType.lowStock => Icons.warning_amber,
    };

    final color = switch (alert.severity) {
      StockAlertSeverity.critical => AlertColors.critical,
      StockAlertSeverity.warning => AlertColors.warning,
    };

    String subtitle = alert.reason ?? alert.message;

    final unit = alert.unitOfExpression;
    final qty = alert.currentQuantity;
    final min = alert.minimumThreshold;

    if (alert.type == StockAlertType.nearExpiry) {
      final b = (alert.batchNumber ?? '').trim();
      final exp = alert.expiryDate;
      final expText = exp == null ? '—' : _formatDate(exp);
      subtitle = 'Near expiry • Batch ${b.isEmpty ? '—' : b} • Exp $expText';
    } else if (qty != null && min != null) {
      final q = unit == null ? '$qty' : '$qty $unit';
      final m = unit == null ? '$min' : '$min $unit';
      subtitle = '${alert.reason ?? 'Stock alert'} • Current $q • Min $m';
    }

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isUnread ? color.withValues(alpha: 0.38) : scheme.outline.withValues(alpha: 0.2),
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
                      Expanded(child: Text(title, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                      const SizedBox(width: 10),
                      if (isUnread) Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(_formatDateTime(alert.createdAt), style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }

  static String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }
}

class _StockAlertDetailSheet extends StatelessWidget {
  final StockAlert alert;

  const _StockAlertDetailSheet({required this.alert});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (alert.severity) {
      StockAlertSeverity.critical => AlertColors.critical,
      StockAlertSeverity.warning => AlertColors.warning,
    };

    String metric(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();

    final name = alert.commodityName ?? alert.title;
    final unit = alert.unitOfExpression;
    final qty = alert.currentQuantity;
    final min = alert.minimumThreshold;

    final qtyText = qty == null ? '—' : (unit == null ? '$qty' : '$qty $unit');
    final minText = min == null ? '—' : (unit == null ? '$min' : '$min $unit');

    final batch = metric(alert.batchNumber);
    final exp = alert.expiryDate == null ? '—' : _StockAlertCard._formatDate(alert.expiryDate!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric(alert.reason), style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(alert.message, style: context.textStyles.bodyMedium?.copyWith(height: 1.45, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (alert.type != StockAlertType.nearExpiry)
                  Row(
                    children: [
                      Expanded(child: _DetailMetric(label: 'Current', value: qtyText)),
                      const SizedBox(width: 12),
                      Expanded(child: _DetailMetric(label: 'Minimum', value: minText)),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: _DetailMetric(label: 'Batch', value: batch)),
                      const SizedBox(width: 12),
                      Expanded(child: _DetailMetric(label: 'Expiry', value: exp)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('Triggered: ${_StockAlertCard._formatDateTime(alert.createdAt)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (alert.readAt != null) ...[
            const SizedBox(height: 6),
            Text('Read: ${_StockAlertCard._formatDateTime(alert.readAt!)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (alert.resolvedAt != null) ...[
            const SizedBox(height: 6),
            Text('Resolved: ${_StockAlertCard._formatDateTime(alert.resolvedAt!)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  final String label;
  final String value;

  const _DetailMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textStyles.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

enum _EmptyMode { none, unread }

class _EmptyAlertsState extends StatelessWidget {
  final _EmptyMode mode;

  const _EmptyAlertsState({required this.mode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final title = switch (mode) {
      _EmptyMode.unread => 'No unread stock alerts',
      _EmptyMode.none => 'No stock alerts yet',
    };

    final subtitle = switch (mode) {
      _EmptyMode.unread => 'All active alerts have been read, or everything is in good shape.',
      _EmptyMode.none => 'Low stock, out of stock, and near-expiry alerts will appear here.',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AlertColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.inventory_2_outlined, color: AlertColors.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
