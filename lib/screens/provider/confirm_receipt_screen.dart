import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/delivery.dart';
import 'package:mediflow/models/notification_item.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/notification_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class ConfirmReceiptScreen extends StatefulWidget {
  final String deliveryId;

  const ConfirmReceiptScreen({super.key, required this.deliveryId});

  @override
  State<ConfirmReceiptScreen> createState() => _ConfirmReceiptScreenState();
}

class _ConfirmReceiptScreenState extends State<ConfirmReceiptScreen> {
  final Map<String, TextEditingController> _qtyCtrls = {};
  final Map<String, String?> _discrepancyReasons = {};
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();
    final inventory = context.watch<InventoryService>();

    final providerId = auth.currentUser?.id ?? '';
    final role = auth.currentUser?.role;
    final isViewOnly = role == UserRole.sfhTeam;
    final deliveries = (role?.hasGlobalView ?? false)
        ? deliveryService.getAllDeliveries()
        : deliveryService.getDeliveriesByProvider(providerId);
    final delivery = deliveries.where((d) => d.id == widget.deliveryId).cast<Delivery?>().firstOrNull;

    if (delivery == null) {
      return Scaffold(appBar: AppBar(title: const Text('Confirm Receipt'), actions: const [AppAccountMenu()]), body: const Center(child: Text('Delivery not found')));
    }

    for (final item in delivery.items) {
      _qtyCtrls.putIfAbsent(item.commodityId, () => TextEditingController(text: (item.quantityReceived ?? item.quantityPushed).toString()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Receipt'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Expanded(
              child: ListView(
                padding: AppSpacing.paddingLg,
                children: [
                  Text('Enter the physical quantities received. If any line differs from pushed quantity, select a discrepancy reason.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  ...delivery.items.map((item) {
                    final ctrl = _qtyCtrls[item.commodityId]!;
                    final received = int.tryParse(ctrl.text.trim()) ?? item.quantityPushed;
                    final differs = received != item.quantityPushed;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.commodityName, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadius.lg)),
                                    child: Row(
                                      children: [
                                        Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text('Pushed: ${item.quantityPushed}', style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: ctrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Qty received'),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                            if (differs) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _discrepancyReasons[item.commodityId],
                                items: const [
                                  DropdownMenuItem(value: 'Damaged', child: Text('Damaged')),
                                  DropdownMenuItem(value: 'Short supply', child: Text('Short supply')),
                                  DropdownMenuItem(value: 'Over supply', child: Text('Over supply')),
                                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                                ],
                                onChanged: (v) => setState(() => _discrepancyReasons[item.commodityId] = v),
                                decoration: const InputDecoration(labelText: 'Discrepancy reason'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_submitting || isViewOnly)
                          ? null
                          : () async {
                              final updatedItems = <DeliveryLineItem>[];
                              for (final item in delivery.items) {
                                final received = int.tryParse(_qtyCtrls[item.commodityId]?.text.trim() ?? '') ?? item.quantityPushed;
                                final differs = received != item.quantityPushed;
                                final reason = _discrepancyReasons[item.commodityId];
                                if (differs && (reason == null || reason.isEmpty)) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Select discrepancy reason for ${item.commodityName}')));
                                  return;
                                }
                                updatedItems.add(item.copyWith(quantityReceived: received, discrepancyReason: differs ? reason : null));
                              }

                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Accept & add to stock?'),
                                  content: const Text('This will confirm receipt and update inventory quantities.'),
                                  actions: [
                                    TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => context.pop(true), child: const Text('Confirm')),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;

                              setState(() => _submitting = true);
                              try {
                                for (final item in updatedItems) {
                                  final received = item.quantityReceived ?? item.quantityPushed;
                                  if (received <= 0) continue;
                                  await inventory.addToStockFromDelivery(commodityId: item.commodityId, commodityNameFallback: item.commodityName, quantity: received, userId: providerId);
                                }

                                final updatedDelivery = delivery.copyWith(status: DeliveryStatus.accepted, items: updatedItems, updatedAt: DateTime.now(), syncStatus: SyncStatus.pending);
                                await deliveryService.updateDelivery(updatedDelivery);

                                final notif = context.read<NotificationService>();
                                await notif.addSystem(title: 'Delivery confirmed', description: 'Stock was updated for ${delivery.items.length} line(s).', type: NotificationType.deliveryArrived);

                                if (!context.mounted) return;
                                context.go('/deliveries/${delivery.id}/success');
                              } finally {
                                if (mounted) setState(() => _submitting = false);
                              }
                            },
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: Text(isViewOnly ? 'View-only access' : 'Accept & Add to Stock'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
