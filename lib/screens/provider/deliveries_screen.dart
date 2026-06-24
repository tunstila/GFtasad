import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/delivery.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/provider_bottom_nav.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();

    final user = auth.currentUser;
    final deliveries = (user?.hasGlobalView ?? false)
        ? deliveryService.getAllDeliveries()
        : deliveryService.getDeliveriesByProvider(user?.id ?? '');
    final pending = deliveries.where((d) => d.status == DeliveryStatus.pending).toList();
    final accepted = deliveries.where((d) => d.status == DeliveryStatus.accepted).toList();

    final deliveryBadge = pending.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: const [AppAccountMenu()],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pending'),
                  const SizedBox(width: 8),
                  if (deliveryBadge > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AlertColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AlertColors.warning.withValues(alpha: 0.35), width: 1)),
                      child: Text('$deliveryBadge', style: context.textStyles.labelSmall?.copyWith(color: AlertColors.warning, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
            const Tab(text: 'Accepted'),
            const Tab(text: 'All'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _DeliveryList(deliveries: pending, emptyText: 'No pending deliveries', onTap: (d) => context.push('/deliveries/${d.id}')),
                  _DeliveryList(deliveries: accepted, emptyText: 'No accepted deliveries', onTap: (d) => context.push('/deliveries/${d.id}')),
                  _DeliveryList(deliveries: deliveries, emptyText: 'No deliveries yet', onTap: (d) => context.push('/deliveries/${d.id}')),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProviderBottomNav(currentIndex: 3, deliveryBadge: deliveryBadge),
    );
  }
}

class _DeliveryList extends StatelessWidget {
  final List<Delivery> deliveries;
  final String emptyText;
  final void Function(Delivery) onTap;

  const _DeliveryList({required this.deliveries, required this.emptyText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (deliveries.isEmpty) {
      return Center(child: Text(emptyText, style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }

    return ListView.separated(
      padding: AppSpacing.paddingLg,
      itemCount: deliveries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final d = deliveries[index];
        final statusColor = switch (d.status) {
          DeliveryStatus.pending => AlertColors.warning,
          DeliveryStatus.accepted => AlertColors.success,
          DeliveryStatus.disputed => AlertColors.critical,
        };

        return InkWell(
          onTap: () => onTap(d),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
            child: Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.local_shipping, color: statusColor)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.supplierName, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text('${_formatDate(d.deliveryDate)} • ${d.items.length} lines • ${d.totalUnits} units', style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1)),
                  child: Text(d.status.name, style: context.textStyles.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }
}
