import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mediflow/models/stock_request.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class StockRequestDetailScreen extends StatelessWidget {
  final String requestId;
  final bool supplierView;

  const StockRequestDetailScreen({super.key, required this.requestId, this.supplierView = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final service = context.watch<StockRequestService>();

    final list = supplierView ? service.supplierRequests : service.providerRequests;
    final request = list.where((e) => e.id == requestId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Details'),
        actions: [
          if (supplierView && request != null && request.status == StockRequestStatus.pending) ...[
            IconButton(
              tooltip: 'Reject',
              onPressed: () async {
                final note = await showModalBottomSheet<String?>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const _SupplierResponseNoteSheet(title: 'Reject request', actionLabel: 'Reject'),
                );
                if (!context.mounted) return;
                try {
                  await context.read<StockRequestService>().supplierReject(requestId: request.id, responseNote: note);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request rejected')));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to reject: $e')));
                }
              },
              icon: Icon(Icons.block, color: scheme.error),
            ),
            IconButton(
              tooltip: 'Accept',
              onPressed: () async {
                final note = await showModalBottomSheet<String?>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const _SupplierResponseNoteSheet(title: 'Accept request', actionLabel: 'Accept'),
                );
                if (!context.mounted) return;
                try {
                  await context.read<StockRequestService>().supplierAccept(requestId: request.id, responseNote: note);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request accepted: delivery created')));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
                }
              },
              icon: Icon(Icons.check_circle, color: scheme.primary),
            ),
          ],
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: request == null
            ? Center(
                child: Padding(
                  padding: AppSpacing.paddingLg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 42, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 10),
                      Text('Request not loaded yet', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text('Pull to refresh on the previous page, then open again.', textAlign: TextAlign.center, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 14),
                      OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  if (user == null) return;
                  if (supplierView) {
                    await context.read<StockRequestService>().loadForSupplier(user.id);
                  } else {
                    await context.read<StockRequestService>().loadForProvider(user.id);
                  }
                },
                child: ListView(
                  padding: AppSpacing.paddingLg,
                  children: [
                    _HeaderCard(request: request, supplierView: supplierView),
                    const SizedBox(height: 12),
                    _ItemsCard(request: request),
                    if ((request.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _NotesCard(notes: request.notes!.trim()),
                    ],
                    if (supplierView) ...[
                      const SizedBox(height: 12),
                      _AddressCard(request: request),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _SupplierResponseNoteSheet extends StatefulWidget {
  final String title;
  final String actionLabel;
  const _SupplierResponseNoteSheet({required this.title, required this.actionLabel});

  @override
  State<_SupplierResponseNoteSheet> createState() => _SupplierResponseNoteSheetState();
}

class _SupplierResponseNoteSheetState extends State<_SupplierResponseNoteSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Response note (optional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.pop(_ctrl.text.trim().isEmpty ? null : _ctrl.text.trim()),
                child: Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final StockRequest request;
  final bool supplierView;

  const _HeaderCard({required this.request, required this.supplierView});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = supplierView ? request.providerName : request.supplierName;
    final subtitle = supplierView ? request.providerEmail : 'Requested by you';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
      child: Row(
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.request_quote, color: scheme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Pill(text: request.status.name, color: scheme.primary),
                    const SizedBox(width: 8),
                    _Pill(text: '${request.items.length} items', color: scheme.secondary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final StockRequest request;

  const _ItemsCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...request.items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(e.commodityName, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
                  Text('${e.quantity} ${e.unit}', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final StockRequest request;

  const _AddressCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCoords = request.providerLatitude != null && request.providerLongitude != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery Address', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          _InfoRow(icon: Icons.location_on, title: 'Address', value: request.providerBusinessAddress ?? '-'),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.map, title: 'State / LGA', value: '${request.providerState ?? '-'} / ${request.providerLga ?? '-'}'),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.gps_fixed, title: 'Coordinates', value: hasCoords ? '${request.providerLatitude}, ${request.providerLongitude}' : 'Not captured'),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final String notes;
  const _NotesCard({required this.notes});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Notes', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(notes, style: context.textStyles.bodyMedium?.copyWith(height: 1.5)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoRow({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: scheme.primary, size: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.textStyles.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(value, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Text(text, style: context.textStyles.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w900)),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
