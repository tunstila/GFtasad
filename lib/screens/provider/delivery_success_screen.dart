import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/delivery.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class DeliverySuccessScreen extends StatelessWidget {
  final String deliveryId;

  const DeliverySuccessScreen({super.key, required this.deliveryId});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();

    final providerId = auth.currentUser?.id ?? '';
    final delivery = deliveryService.getDeliveriesByProvider(providerId).where((d) => d.id == deliveryId).cast<Delivery?>().firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Success'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AlertColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AlertColors.success.withValues(alpha: 0.35), width: 1)),
                child: Row(
                  children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AlertColors.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.verified, color: AlertColors.success)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Delivery confirmed', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                          const SizedBox(height: 6),
                          Text('Stock has been added to your inventory.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (delivery != null) ...[
                Text('Summary', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                ...delivery.items.map((i) {
                  final received = i.quantityReceived ?? i.quantityPushed;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
                      child: Row(
                        children: [
                          Expanded(child: Text(i.commodityName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                          const SizedBox(width: 10),
                          Text('+$received', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: AlertColors.success)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/inventory'),
                  icon: const Icon(Icons.inventory_2, color: Colors.white),
                  label: const Text('View Updated Inventory'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/provider-home'),
                  icon: Icon(Icons.home, color: Theme.of(context).colorScheme.primary),
                  label: const Text('Go to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
