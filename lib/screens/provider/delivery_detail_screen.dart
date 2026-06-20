import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/delivery.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class DeliveryDetailScreen extends StatelessWidget {
  final String deliveryId;

  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();

    final user = auth.currentUser;
    final deliveries = (user?.effectiveRole.hasGlobalView ?? false)
        ? deliveryService.getAllDeliveries()
        : deliveryService.getDeliveriesByProvider(user?.id ?? '');
    final delivery = deliveries.where((d) => d.id == deliveryId).cast<Delivery?>().firstOrNull;

    if (delivery == null) {
      return Scaffold(appBar: AppBar(title: const Text('Delivery'), actions: const [AppAccountMenu()]), body: const Center(child: Text('Delivery not found')));
    }

    final statusColor = switch (delivery.status) {
      DeliveryStatus.pending => AlertColors.warning,
      DeliveryStatus.accepted => AlertColors.success,
      DeliveryStatus.disputed => AlertColors.critical,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Detail'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Expanded(
              child: ListView(
                padding: AppSpacing.paddingLg,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(delivery.supplierName, style: context.textStyles.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 10),
                                  Text('Pushed: ${_formatDateTime(delivery.deliveryDate)}', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  if (delivery.reference != null) ...[
                                    const SizedBox(height: 6),
                                    Text('Ref: ${delivery.reference}', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1)),
                              child: Text(delivery.status.name, style: context.textStyles.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Line items', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ...delivery.items.map((i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadius.lg)),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(i.commodityName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                                    const SizedBox(width: 10),
                                    Text('${i.quantityPushed}', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (delivery.status == DeliveryStatus.pending && (user?.effectiveRole.canConfirmDeliveries ?? false))
                          ? () => context.push('/deliveries/${delivery.id}/confirm')
                          : null,
                      icon: const Icon(Icons.verified, color: Colors.white),
                      label: Text((user?.effectiveRole.canConfirmDeliveries ?? false) ? 'Confirm Physical Receipt' : 'View-only access'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Issue flow not yet implemented')));
                      },
                      icon: Icon(Icons.report_problem, color: Theme.of(context).colorScheme.primary),
                      label: const Text('Raise Issue'),
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
