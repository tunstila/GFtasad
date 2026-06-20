import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/program_badge.dart';
import 'package:mediflow/widgets/provider_bottom_nav.dart';
import 'package:mediflow/widgets/stock_status_badge.dart';

class CommodityDetailScreen extends StatelessWidget {
  final String commodityId;

  const CommodityDetailScreen({super.key, required this.commodityId});

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

    final commodity = inventory.commodities.where((c) => c.id == commodityId).cast<Commodity?>().firstOrNull;
    if (commodity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Commodity'), actions: const [AppAccountMenu()]),
        body: const Center(child: Text('Commodity not found')),
        bottomNavigationBar: ProviderBottomNav(currentIndex: 2, deliveryBadge: deliveryBadge),
      );
    }

    final computed = inventory.withComputedQuantity(commodity: commodity, userId: userId);
    final unit = inventory.getEffectiveUnitOfExpressionForUser(userId: userId, commodity: commodity);
    final batchSettings = inventory.getBatchNumberForUser(userId: userId, commodityId: commodity.id);
    final expirySettings = inventory.getExpiryDateForUser(userId: userId, commodityId: commodity.id);

    final batchRows = (role == UserRole.fieldProvider)
        ? inventory.getBatchBreakdownForUser(userId: userId, commodityId: commodity.id)
        : const <InventoryBatchBreakdownRow>[];
    final expiryRows = (role == UserRole.fieldProvider)
        ? inventory.getExpiryBreakdownForUser(userId: userId, commodityId: commodity.id)
        : const <InventoryExpiryBreakdownRow>[];
    final allMoves = inventory.getMovementsByCommodity(commodity.id);
    final movements = (role?.hasGlobalView ?? false) ? allMoves : allMoves.where((m) => m.userId == userId).toList();
    final ratio = computed.minThreshold <= 0 ? 1.0 : (computed.currentQuantity / (computed.minThreshold * 2)).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commodity'),
        actions: [
          IconButton(
            tooltip: 'Adjust Stock',
            onPressed: (role?.canAdjustStock ?? false)
                ? () => context.push('/inventory/adjust?commodityId=${commodity.id}')
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('View-only access: stock adjustment is disabled.')),
                    );
                  },
            icon: const Icon(Icons.tune),
          ),
          const AppAccountMenu(),
        ],
      ),
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
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25), width: 1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(computed.name, style: context.textStyles.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 10),
                                  ProgramBadge(program: computed.program),
                                ],
                              ),
                            ),
                            StockStatusBadge(status: computed.status),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(child: _MetricTile(label: 'Current stock', value: inventory.formatQuantityForUser(userId: userId, commodity: commodity, quantity: computed.currentQuantity, showNotSet: true), icon: Icons.inventory_2)),
                            const SizedBox(width: 12),
                            Expanded(child: _MetricTile(label: 'Minimum threshold', value: inventory.formatQuantityForUser(userId: userId, commodity: commodity, quantity: computed.minThreshold, showNotSet: true), icon: Icons.safety_check)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Stock level', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          child: SizedBox(
                            height: 12,
                            child: Stack(
                              children: [
                                Positioned.fill(child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)),
                                Positioned.fill(
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: ratio,
                                    child: AnimatedContainer(duration: const Duration(milliseconds: 240), decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.45)]))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Last updated: ${_formatDateTime(computed.updatedAt)}', style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Batch & expiry', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 10),
                              _InfoRow(label: 'Batch Number', value: (batchSettings == null || batchSettings.trim().isEmpty) ? 'Not set' : batchSettings),
                              const SizedBox(height: 8),
                              _InfoRow(label: 'Expiry Date', value: expirySettings == null ? 'Not set' : _formatDateOnly(expirySettings)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: (role == UserRole.fieldProvider)
                              ? () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    showDragHandle: true,
                                    builder: (_) => _EditBatchExpirySheetForDetail(userId: userId, commodity: commodity),
                                  )
                              : null,
                          icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (role == UserRole.fieldProvider) ...[
                    Text('Batches', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (batchRows.isEmpty)
                      Text('No active batches yet. Receive stock to create batch rows.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))
                    else
                      ...batchRows.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BatchRowCard(
                              row: r,
                              unitOfExpression: unit,
                              onBackfill: (r.movementIdsWithMissingData.isEmpty)
                                  ? null
                                  : () async {
                                      final targetMovementId = r.movementIdsWithMissingData.first;
                                      await showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        showDragHandle: true,
                                        builder: (_) => _BackfillBatchExpiryMovementSheet(
                                          commodityName: commodity.name,
                                          unitOfExpression: unit,
                                          movementId: targetMovementId,
                                        ),
                                      );
                                    },
                            ),
                          )),
                    const SizedBox(height: 18),
                    Text('Expiry breakdown', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (expiryRows.isEmpty)
                      Text('No expiry dates recorded yet.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))
                    else
                      ...expiryRows.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ExpiryRowCard(row: e, unitOfExpression: unit),
                          )),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => context.push('/inventory/adjust?commodityId=${commodity.id}'),
                          icon: const Icon(Icons.edit, color: Colors.white),
                          label: const Text('Adjust'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/inventory/movements?commodityId=${commodity.id}'),
                          icon: Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                          label: const Text('History'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text('Movement history', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  if (movements.isEmpty)
                    Text('No stock movements yet.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))
                  else
                    ...movements.take(12).map((m) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _MovementRow(movement: m, commodityName: commodity.name, unitOfExpression: unit))),
                ],
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

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)), child: Icon(icon, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.textStyles.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(value, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700))),
        const SizedBox(width: 10),
        Flexible(child: Text(value, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _EditBatchExpirySheetForDetail extends StatefulWidget {
  final String userId;
  final Commodity commodity;

  const _EditBatchExpirySheetForDetail({required this.userId, required this.commodity});

  @override
  State<_EditBatchExpirySheetForDetail> createState() => _EditBatchExpirySheetForDetailState();
}

class _EditBatchExpirySheetForDetailState extends State<_EditBatchExpirySheetForDetail> {
  final _batchCtrl = TextEditingController();
  DateTime? _expiry;
  String? _unit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final inventory = context.read<InventoryService>();
    _batchCtrl.text = inventory.getBatchNumberForUser(userId: widget.userId, commodityId: widget.commodity.id) ?? '';
    _expiry = inventory.getExpiryDateForUser(userId: widget.userId, commodityId: widget.commodity.id);
    _unit = inventory.getEffectiveUnitOfExpressionForUser(userId: widget.userId, commodity: widget.commodity);
  }

  @override
  void dispose() {
    _batchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final now = DateTime.now();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit batch & expiry', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: _batchCtrl, decoration: const InputDecoration(labelText: 'Batch Number (optional)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _unit,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                ...UnitOfExpression.allowed.map((u) => DropdownMenuItem<String?>(value: u, child: Text(u))),
              ],
              onChanged: (v) => setState(() => _unit = v),
              decoration: const InputDecoration(labelText: 'Unit of expression'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final initial = _expiry ?? now.add(const Duration(days: 180));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: now.subtract(const Duration(days: 3650)),
                  lastDate: now.add(const Duration(days: 3650)),
                  helpText: 'Select expiry date',
                );
                if (picked != null && mounted) setState(() => _expiry = picked);
              },
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expiry Date (optional)'),
                child: Text(_expiry == null ? 'Not set' : _formatDateOnly(_expiry!)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final expiry = _expiry == null ? null : DateTime(_expiry!.year, _expiry!.month, _expiry!.day);
                        setState(() => _saving = true);
                        try {
                          await inventory.setBatchExpiryForUser(userId: widget.userId, commodityId: widget.commodity.id, batchNumber: _batchCtrl.text, expiryDate: expiry, unitOverride: _unit);
                          if (!context.mounted) return;
                          context.pop();
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Save changes'),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

String _formatDateOnly(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

class _BatchRowCard extends StatelessWidget {
  final InventoryBatchBreakdownRow row;
  final String? unitOfExpression;
  final VoidCallback? onBackfill;

  const _BatchRowCard({required this.row, required this.unitOfExpression, required this.onBackfill});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final batchLabel = (row.batchNumber == null || row.batchNumber!.trim().isEmpty) ? 'Missing batch number' : row.batchNumber!.trim();
    final expiryLabel = row.expiryDate == null ? 'Missing expiry date' : _formatDateOnly(row.expiryDate!);
    final qtyLabel = unitOfExpression == null ? '${row.quantity}' : '${row.quantity} $unitOfExpression';
    final hasMissing = (row.batchNumber == null || row.batchNumber!.trim().isEmpty) || row.expiryDate == null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: hasMissing ? scheme.error.withValues(alpha: 0.35) : scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: hasMissing ? scheme.error.withValues(alpha: 0.12) : scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(hasMissing ? Icons.error_outline : Icons.inventory_2, color: hasMissing ? scheme.error : scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(batchLabel, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Expiry: $expiryLabel', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                if (row.lastReceivedAt != null) ...[
                  const SizedBox(height: 4),
                  Text('Last received: ${row.lastReceivedAt!.year}-${row.lastReceivedAt!.month.toString().padLeft(2, '0')}-${row.lastReceivedAt!.day.toString().padLeft(2, '0')}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(qtyLabel, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              if (onBackfill != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onBackfill,
                  icon: Icon(Icons.edit, color: scheme.primary),
                  label: const Text('Fix missing'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpiryRowCard extends StatelessWidget {
  final InventoryExpiryBreakdownRow row;
  final String? unitOfExpression;

  const _ExpiryRowCard({required this.row, required this.unitOfExpression});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expiryLabel = row.expiryDate == null ? 'Missing expiry date' : _formatDateOnly(row.expiryDate!);
    final qtyLabel = unitOfExpression == null ? '${row.quantity}' : '${row.quantity} $unitOfExpression';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
      child: Row(
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: scheme.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.event, color: scheme.secondary)),
          const SizedBox(width: 12),
          Expanded(child: Text(expiryLabel, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
          Text(qtyLabel, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _BackfillBatchExpiryMovementSheet extends StatefulWidget {
  final String commodityName;
  final String? unitOfExpression;
  final String movementId;

  const _BackfillBatchExpiryMovementSheet({required this.commodityName, required this.unitOfExpression, required this.movementId});

  @override
  State<_BackfillBatchExpiryMovementSheet> createState() => _BackfillBatchExpiryMovementSheetState();
}

class _BackfillBatchExpiryMovementSheetState extends State<_BackfillBatchExpiryMovementSheet> {
  final _batchCtrl = TextEditingController();
  DateTime? _expiry;
  bool _saving = false;

  @override
  void dispose() {
    _batchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final now = DateTime.now();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backfill missing batch/expiry', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(widget.commodityName, style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(controller: _batchCtrl, decoration: const InputDecoration(labelText: 'Batch number', prefixIcon: Icon(Icons.confirmation_number))),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final initial = _expiry ?? now.add(const Duration(days: 180));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: now.subtract(const Duration(days: 3650)),
                  lastDate: now.add(const Duration(days: 3650)),
                  helpText: 'Select expiry date',
                );
                if (picked != null && mounted) setState(() => _expiry = picked);
              },
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expiry date'),
                child: Text(_expiry == null ? 'Select a date' : _formatDateOnly(_expiry!)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final batch = _batchCtrl.text.trim();
                        if (batch.isEmpty && _expiry == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter batch number and/or expiry date.')));
                          return;
                        }
                        setState(() => _saving = true);
                        try {
                          await inventory.backfillMissingBatchExpiryOnMovement(
                            movementId: widget.movementId,
                            batchNumber: batch.isEmpty ? null : batch,
                            expiryDate: _expiry,
                          );
                          if (!context.mounted) return;
                          context.pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated.')));
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final StockMovement movement;
  final String commodityName;
  final String? unitOfExpression;

  const _MovementRow({required this.movement, required this.commodityName, required this.unitOfExpression});

  @override
  Widget build(BuildContext context) {
    final sign = movement.type == MovementType.add ? '+' : '-';
    final color = movement.type == MovementType.add ? AlertColors.success : AlertColors.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1)),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(movement.type == MovementType.add ? Icons.add : Icons.remove, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$commodityName • ${movement.reason.name}', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(_formatDateTime(movement.createdAt), style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(unitOfExpression == null ? '$sign${movement.quantity}' : '$sign${movement.quantity} $unitOfExpression', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
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

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
