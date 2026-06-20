import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/provider_bottom_nav.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class StockMovementHistoryScreen extends StatefulWidget {
  final String? preselectedCommodityId;

  const StockMovementHistoryScreen({super.key, this.preselectedCommodityId});

  @override
  State<StockMovementHistoryScreen> createState() => _StockMovementHistoryScreenState();
}

class _StockMovementHistoryScreenState extends State<StockMovementHistoryScreen> {
  String? _commodityId;
  MovementType? _type;

  @override
  void initState() {
    super.initState();
    _commodityId = widget.preselectedCommodityId;
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();

    final userId = auth.currentUser?.id ?? '';
    final role = auth.currentUser?.role;
    final deliveryBadge = (role?.hasGlobalView ?? false)
        ? deliveryService.getPendingDeliveriesCountAll()
        : deliveryService.getPendingDeliveriesCount(userId);

    final commodities = role == UserRole.fieldProvider ? inventory.getFacilityCommodities(userId) : inventory.commodities;
    var movements = (role?.hasGlobalView ?? false) ? inventory.movements : inventory.movements.where((m) => m.userId == userId).toList();

    if (_commodityId != null) movements = movements.where((m) => m.commodityId == _commodityId).toList();
    if (_type != null) movements = movements.where((m) => m.type == _type).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movements'),
        actions: [
          IconButton(
            tooltip: 'Clear filters',
            onPressed: () => setState(() {
              _commodityId = null;
              _type = null;
            }),
            icon: const Icon(Icons.filter_alt_off),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Padding(
              padding: AppSpacing.horizontalLg,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _commodityId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All commodities')),
                            ...commodities.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                          ],
                          onChanged: (v) => setState(() => _commodityId = v),
                          decoration: const InputDecoration(labelText: 'Commodity'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<MovementType>(
                          value: _type,
                          items: const [
                            DropdownMenuItem(value: null, child: Text('All types')),
                            DropdownMenuItem(value: MovementType.add, child: Text('Add')),
                            DropdownMenuItem(value: MovementType.deduct, child: Text('Deduct')),
                          ],
                          onChanged: (v) => setState(() => _type = v),
                          decoration: const InputDecoration(labelText: 'Type'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            Expanded(
              child: movements.isEmpty
                  ? Center(child: Text('No movements found', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                  : ListView.separated(
                      padding: AppSpacing.paddingLg,
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final m = movements[index];
                        final commodityName = commodities.where((c) => c.id == m.commodityId).cast<Commodity?>().firstOrNull?.name ?? 'Commodity';
                        final sign = m.type == MovementType.add ? '+' : '-';
                        final color = m.type == MovementType.add ? AlertColors.success : AlertColors.warning;
                        final syncColor = switch (m.syncStatus) {
                          SyncStatus.synced => SyncColors.synced,
                          SyncStatus.pending => SyncColors.pending,
                          SyncStatus.syncing => SyncColors.syncing,
                          SyncStatus.failed => SyncColors.failed,
                        };

                        return InkWell(
                          onTap: () {},
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
                            child: Row(
                              children: [
                                Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(m.type == MovementType.add ? Icons.add : Icons.remove, color: color)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(commodityName, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 6),
                                      Text('${m.reason.name} • ${_formatDateTime(m.createdAt)}', style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$sign${m.quantity}', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(width: 8, height: 8, decoration: BoxDecoration(color: syncColor, shape: BoxShape.circle)),
                                        const SizedBox(width: 6),
                                        Text(m.syncStatus.name, style: context.textStyles.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProviderBottomNav(currentIndex: 2, deliveryBadge: deliveryBadge),
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

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
