import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final records = context.watch<TestRecordService>();
    final inventory = context.watch<InventoryService>();
    final deliveries = context.watch<DeliveryService>();

    final userId = auth.currentUser?.id ?? '';

    final pendingRecords = records.records.where((r) => r.syncStatus != SyncStatus.synced).toList();
    final pendingMovements = inventory.movements.where((m) => m.syncStatus != SyncStatus.synced).toList();
    final pendingDeliveries = deliveries.getDeliveriesByProvider(userId).where((d) => d.syncStatus != SyncStatus.synced).toList();

    final totalPending = pendingRecords.length + pendingMovements.length + pendingDeliveries.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        actions: [
          TextButton.icon(
            onPressed: _syncing
                ? null
                : () async {
                    setState(() => _syncing = true);
                    try {
                      // Production-safe: only mark items as synced after remote writes succeed.
                      // Test records implement a real push/pull sync; other modules may be best-effort.
                      await records.syncNow();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync complete')));
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: ${e.toString()}')));
                    } finally {
                      if (mounted) setState(() => _syncing = false);
                    }
                  },
            icon: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
            label: const Text('Sync Now'),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.paddingLg,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
              child: Row(
                children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: SyncColors.pending.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.cloud_upload, color: SyncColors.pending)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$totalPending pending item(s)', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text('Queued changes will sync when connected.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Pending offline records', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...pendingRecords.map((r) => _PendingTestRecordRow(record: r)),
            ...pendingMovements.map((m) => _PendingRow(type: 'Stock movement', timestamp: m.createdAt, status: m.syncStatus)),
            ...pendingDeliveries.map((d) => _PendingRow(type: 'Delivery update', timestamp: d.updatedAt, status: d.syncStatus)),
            if (totalPending == 0)
              Text('All caught up.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
                label: const Text('Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final String type;
  final DateTime timestamp;
  final SyncStatus status;

  const _PendingRow({required this.type, required this.timestamp, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.synced => SyncColors.synced,
      SyncStatus.pending => SyncColors.pending,
      SyncStatus.syncing => SyncColors.syncing,
      SyncStatus.failed => SyncColors.failed,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.receipt_long, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(_formatDateTime(timestamp), style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: color.withValues(alpha: 0.35), width: 1)),
              child: Text(status.name, style: context.textStyles.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
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

class _PendingTestRecordRow extends StatelessWidget {
  final TestRecord record;

  const _PendingTestRecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<TestRecordService>();
    final color = switch (record.syncStatus) {
      SyncStatus.synced => SyncColors.synced,
      SyncStatus.pending => SyncColors.pending,
      SyncStatus.syncing => SyncColors.syncing,
      SyncStatus.failed => SyncColors.failed,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => showModalBottomSheet(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => _PendingTestRecordDetailSheet(record: record),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.receipt_long, color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${record.program.name.toUpperCase()} • ${record.clientName}', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(_formatDateTime(record.createdAt), style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    if (record.syncStatus == SyncStatus.failed && (record.lastError ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(record.lastError!, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (record.syncStatus == SyncStatus.failed || record.syncStatus == SyncStatus.pending)
                OutlinedButton(
                  onPressed: record.syncStatus == SyncStatus.syncing ? null : () => svc.syncRecordInBackground(record.id),
                  child: const Text('Retry'),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: color.withValues(alpha: 0.35), width: 1)),
                  child: Text(record.syncStatus.name, style: context.textStyles.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
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

class _PendingTestRecordDetailSheet extends StatelessWidget {
  final TestRecord record;

  const _PendingTestRecordDetailSheet({required this.record});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<TestRecordService>();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pending Test Record', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('${record.program.name.toUpperCase()} • ${record.clientName}', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Client ID: ${record.clientId}', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text('Status: ${record.syncStatus.name}', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text('Retry count: ${record.retryCount}', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            if (record.lastAttemptedAt != null) ...[
              const SizedBox(height: 6),
              Text('Last attempted: ${record.lastAttemptedAt}', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if ((record.lastError ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: scheme.error.withValues(alpha: 0.25))),
                child: Text(record.lastError!, style: context.textStyles.bodySmall?.copyWith(color: scheme.onErrorContainer, height: 1.4)),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: record.syncStatus == SyncStatus.syncing ? null : () async {
                context.pop();
                await svc.syncRecordInBackground(record.id);
              },
              icon: const Icon(Icons.sync),
              label: const Text('Retry sync'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
