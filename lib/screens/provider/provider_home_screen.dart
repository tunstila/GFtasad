import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/notification_service.dart';
import 'package:mediflow/services/prevention_messaging_service.dart';
import 'package:mediflow/services/stock_alert_service.dart';
import 'package:mediflow/models/stock_request.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/models/delivery.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/metric_card.dart';
import 'package:mediflow/widgets/program_badge.dart';
import 'package:mediflow/widgets/provider_bottom_nav.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'dart:math' as math;

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  bool _bootstrappedAdminSnapshot = false;
  String? _supplierRequestsLoadedForUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    // Supplier: load once per signed-in user to avoid fetch loops caused by provider notifications.
    if (user != null && user.role == UserRole.supplier) {
      if (_supplierRequestsLoadedForUserId != user.id) {
        _supplierRequestsLoadedForUserId = user.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<StockRequestService>().loadForSupplier(user.id);
        });
      }
    }

    if (!_bootstrappedAdminSnapshot && user?.hasGlobalView == true) {
      _bootstrappedAdminSnapshot = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final svc = context.read<TestRecordService>();
          await svc.syncAllForAdmin();
          await svc.startRealtime(forAdmin: true, userId: user!.id);
        } catch (e) {
          debugPrint('ProviderHome admin bootstrap failed: $e');
        }
      });
    }

    // Keep Stock Alerts tile count correct when returning to Home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StockAlertService>().refresh();
      context.read<NotificationService>().refresh();

      // Auto-sync any pending offline test records when we return to Home.
      // This is a lightweight best-effort sync (won't block UI).
      context.read<TestRecordService>().syncPendingInBackground();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final testRecordService = context.watch<TestRecordService>();
    final inventoryService = context.watch<InventoryService>();
    final deliveryService = context.watch<DeliveryService>();
    final stockAlertService = context.watch<StockAlertService>();
    final stockRequestService = context.watch<StockRequestService>();

    final user = authService.currentUser;
    final userId = user?.id ?? '';

    // =========================================================
    // Supplier Home
    // =========================================================
    if (user?.role == UserRole.supplier) {
      final incoming = stockRequestService.supplierRequests.where((r) => r.status == StockRequestStatus.pending).length;
      final rejected = stockRequestService.supplierRequests.where((r) => r.status == StockRequestStatus.rejected).length;
      final fulfilled = stockRequestService.supplierRequests.where((r) => r.status == StockRequestStatus.approved).length;
      final pendingDeliveries = deliveryService.getPendingDeliveriesCountForSupplier(userId);

      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const OfflineBanner(isOffline: false),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await Future.wait([
                      stockRequestService.loadForSupplier(userId),
                      deliveryService.initialize(),
                    ]);
                  },
                  child: SingleChildScrollView(
                    padding: AppSpacing.paddingLg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Supplier Dashboard', style: context.textStyles.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 4),
                                  Text(user?.displayName ?? 'Supplier', style: context.textStyles.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const AppAccountMenu(),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: MetricCard(
                                title: 'Incoming Requests',
                                value: '$incoming',
                                icon: Icons.inbox,
                                color: incoming > 0 ? AlertColors.info : null,
                                onTap: () => context.push('/supplier/stock-requests?status=pending'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: MetricCard(
                                title: 'Rejected Requests',
                                value: '$rejected',
                                icon: Icons.block,
                                color: rejected > 0 ? AlertColors.warning : null,
                                onTap: () => context.push('/supplier/stock-requests?status=rejected'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: MetricCard(
                                title: 'Fulfilled Requests',
                                value: '$fulfilled',
                                icon: Icons.task_alt,
                                color: fulfilled > 0 ? AlertColors.success : null,
                                onTap: () => context.push('/supplier/stock-requests?status=approved'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: MetricCard(
                                title: 'Pending Deliveries',
                                value: '$pendingDeliveries',
                                icon: Icons.local_shipping,
                                color: pendingDeliveries > 0 ? AlertColors.info : null,
                                onTap: () => context.push('/deliveries'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ProviderBottomNav(currentIndex: 0, deliveryBadge: pendingDeliveries),
      );
    }

    final todayCounts = (user?.hasGlobalView ?? false)
        ? testRecordService.getTodayCountsByProgramAll()
        : testRecordService.getTodayCountsByProgram(userId);
    final stockAlertsUnread = stockAlertService.unreadActiveCount;
    final pendingDeliveries = deliveryService.getPendingDeliveriesCount(user?.id ?? '');
    final pendingSync = testRecordService.getPendingSyncCount();
    final lifetimeCountFuture = (user?.hasGlobalView ?? false)
        ? testRecordService.fetchLifetimeTotalCount()
        : testRecordService.fetchLifetimeTotalCount(userId: userId);
    final messagingTodayFuture = context.read<PreventionMessagingService>().fetchMyTodayCount();

    final recentTests = userId.isEmpty
        ? const <TestRecord>[]
        : testRecordService.records.where((r) => r.userId == userId).take(5).toList();

    final expectedDeliveries = userId.isEmpty
        ? const <Delivery>[]
        : deliveryService.deliveries
            .where((d) => d.providerId == userId && d.status == DeliveryStatus.pending)
            .take(3)
            .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    (user?.hasGlobalView ?? false) ? testRecordService.syncAllForAdmin() : testRecordService.initialize(),
                    inventoryService.initialize(),
                    deliveryService.initialize(),
                    context.read<PreventionMessagingService>().initialize(),
                  ]);
                },
                child: SingleChildScrollView(
                  padding: AppSpacing.paddingLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Good ${_getGreeting()}',
                                  style: context.textStyles.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (user?.facilityName ?? '').trim().isNotEmpty ? user!.facilityName!.trim() : (user?.displayName ?? 'User'),
                                  style: context.textStyles.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if ((user?.facilityName ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    user?.displayName ?? 'User',
                                    style: context.textStyles.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (user?.role == UserRole.fieldProvider && (user?.fieldProviderUniqueId ?? '').trim().isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                user!.fieldProviderUniqueId!,
                                style: context.textStyles.labelMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          GestureDetector(
                            onTap: () => context.push('/sync-status'),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: pendingSync > 0
                                    ? SyncColors.pending.withValues(alpha: 0.1)
                                    : SyncColors.synced.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                pendingSync > 0 ? Icons.cloud_upload : Icons.cloud_done,
                                color: pendingSync > 0 ? SyncColors.pending : SyncColors.synced,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const AppAccountMenu(),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Tests Today',
                              value: '${todayCounts.values.fold(0, (a, b) => a + b)}',
                              icon: Icons.task_alt,
                              onTap: () => context.push('/test-records?today=1'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Stock Alerts',
                              value: '$stockAlertsUnread',
                              icon: Icons.warning,
                              color: stockAlertsUnread > 0 ? AlertColors.warning : null,
                              onTap: () async {
                                await context.push('/stock-alerts');
                                if (!context.mounted) return;
                                await context.read<StockAlertService>().refresh();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FutureBuilder<int?>(
                              future: lifetimeCountFuture,
                              builder: (context, snap) {
                                final v = snap.data;
                                final fallback = testRecordService.localLifetimeCount(userId: userId, hasGlobalView: user?.hasGlobalView ?? false);
                                final effective = v == null ? fallback : math.max(v, fallback);
                                return MetricCard(
                                  title: 'Lifetime Tests',
                                  value: '$effective',
                                  icon: Icons.all_inbox_outlined,
                                  onTap: () => context.push('/lifetime-tests'),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Pending Sync',
                              value: '$pendingSync',
                              icon: Icons.sync,
                              color: pendingSync > 0 ? SyncColors.pending : SyncColors.synced,
                              onTap: () => context.push('/sync-status'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Deliveries',
                              value: '$pendingDeliveries',
                              icon: Icons.local_shipping,
                              color: pendingDeliveries > 0 ? AlertColors.info : null,
                              onTap: () => context.push('/deliveries'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FutureBuilder<int?>(
                              future: messagingTodayFuture,
                              builder: (context, snap) {
                                final v = snap.data;
                                final fallback = context.read<PreventionMessagingService>().localMyTodayCount(userId);
                                final effective = v ?? fallback;
                                return MetricCard(
                                  title: 'Messaging',
                                  value: '$effective',
                                  icon: Icons.campaign,
                                  color: effective > 0 ? ProgramColors.preventionMessaging : null,
                                  onTap: () => context.push('/messaging?today=1'),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: MetricCard(
                          title: 'Notifications',
                          value: '${context.watch<NotificationService>().unreadCount}',
                          icon: Icons.notifications_none,
                          color: context.watch<NotificationService>().unreadCount > 0 ? AlertColors.info : null,
                          onTap: () => context.push('/notifications'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Today\'s Tests by Program',
                        style: context.textStyles.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildProgramCard(
                        context,
                        HealthProgram.malaria,
                        todayCounts[HealthProgram.malaria] ?? 0,
                      ),
                      const SizedBox(height: 12),
                      _buildProgramCard(
                        context,
                        HealthProgram.hiv,
                        todayCounts[HealthProgram.hiv] ?? 0,
                      ),

                      const SizedBox(height: 24),
                      ProviderExpectedDeliveriesPanel(deliveries: expectedDeliveries, onViewAll: () => context.push('/deliveries')),

                      const SizedBox(height: 12),
                      ProviderRecentTestsPanel(records: recentTests, onViewAll: () => context.push('/test-records')),

                      const SizedBox(height: 24),
                      Text(
                        'Quick Actions',
                        style: context.textStyles.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (user?.effectiveRole.canRecordTests ?? false)
                              ? () => context.push('/select-program')
                              : null,
                          icon: const Icon(Icons.add_circle, color: Colors.white),
                          label: const Text('Record Test'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/inventory'),
                          icon: Icon(Icons.inventory_2, color: Theme.of(context).colorScheme.primary),
                          label: const Text('View Inventory'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/deliveries'),
                          icon: Icon(Icons.local_shipping, color: Theme.of(context).colorScheme.primary),
                          label: const Text('Confirm Delivery'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProviderBottomNav(currentIndex: 0, deliveryBadge: pendingDeliveries),
    );
  }

  Widget _buildProgramCard(BuildContext context, HealthProgram program, int count) {
    final color = _getProgramColor(program);
    return GestureDetector(
      onTap: () => context.push('/test-records?today=1&program=${program.name}'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_getProgramIcon(program), color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProgramBadge(program: program),
                  const SizedBox(height: 8),
                  Text(
                    '$count test${count != 1 ? 's' : ''} recorded today',
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$count',
              style: context.textStyles.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgramColor(HealthProgram program) {
    if (program == HealthProgram.malaria) return ProgramColors.malaria;
    if (program == HealthProgram.hiv) return ProgramColors.hiv;
    if (program == HealthProgram.tb) return ProgramColors.tb;
    return ProgramColors.malaria;
  }

  IconData _getProgramIcon(HealthProgram program) {
    if (program == HealthProgram.malaria) return Icons.bug_report;
    if (program == HealthProgram.hiv) return Icons.favorite;
    if (program == HealthProgram.tb) return Icons.air;
    return Icons.bug_report;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

}

class ProviderExpectedDeliveriesPanel extends StatelessWidget {
  final List<Delivery> deliveries;
  final VoidCallback onViewAll;

  const ProviderExpectedDeliveriesPanel({super.key, required this.deliveries, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Expected Deliveries', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              TextButton(onPressed: onViewAll, child: const Text('View all')),
            ],
          ),
          const SizedBox(height: 8),
          if (deliveries.isEmpty)
            Text('No pending deliveries.', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          else
            ...deliveries.map((d) => _DeliveryRow(delivery: d)),
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  final Delivery delivery;

  const _DeliveryRow({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.local_shipping_outlined, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(delivery.reference ?? 'Delivery', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${delivery.items.length} item(s) • ${delivery.supplierName}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class ProviderRecentTestsPanel extends StatelessWidget {
  final List<TestRecord> records;
  final VoidCallback onViewAll;

  const ProviderRecentTestsPanel({super.key, required this.records, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('My Recent Tests', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              TextButton(onPressed: onViewAll, child: const Text('History')),
            ],
          ),
          const SizedBox(height: 8),
          if (records.isEmpty)
            Text('No tests recorded yet.', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          else
            ...records.map((r) => _RecentTestRow(record: r)),
        ],
      ),
    );
  }
}

class _RecentTestRow extends StatelessWidget {
  final TestRecord record;

  const _RecentTestRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (record.program) {
      HealthProgram.malaria => ProgramColors.malaria,
      HealthProgram.hiv => ProgramColors.hiv,
      HealthProgram.tb => ProgramColors.tb,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.task_alt, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.clientName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${record.program.name.toUpperCase()} • ${_formatDate(record.testDate)}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
