import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/models/test_record.dart';
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

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  HealthProgram? _filterProgram;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final auth = context.watch<AuthService>();
    final deliveryService = context.watch<DeliveryService>();

    final userId = auth.currentUser?.id ?? '';
    final role = auth.currentUser?.role;
    final isViewOnly = role == UserRole.sfhTeam;
    final canEditThresholds = role == UserRole.fieldProvider && !isViewOnly;
    final deliveryBadge = (role?.hasGlobalView ?? false)
        ? deliveryService.getPendingDeliveriesCountAll()
        : deliveryService.getPendingDeliveriesCount(userId);

    // Facility inventory for field providers used to be restricted to commodities that have at least one
    // movement for the current user. That made the Inventory tab look empty for new accounts.
    // Instead, we always show the master list (already allowlisted in InventoryService) and compute
    // quantities from movements (which will be 0 until stock is added).
    final all = inventory.commodities;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = all.map((c) => inventory.withComputedQuantity(commodity: c, userId: userId)).where((c) {
      final programOk = _filterProgram == null || c.program == _filterProgram;
      final queryOk = query.isEmpty || c.name.toLowerCase().contains(query);
      return programOk && queryOk;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Stock Movement History',
            onPressed: () => context.push('/inventory/movements'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Manual Stock Adjustment',
            onPressed: (role?.canAdjustStock ?? false)
                ? () => context.push('/inventory/adjust')
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
            Padding(
              padding: AppSpacing.horizontalLg,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search commodities…',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ProgramFilterChip(
                          label: 'All',
                          selected: _filterProgram == null,
                          onTap: () => setState(() => _filterProgram = null),
                        ),
                        const SizedBox(width: 8),
                        _ProgramFilterChip(
                          label: 'Malaria',
                          selected: _filterProgram == HealthProgram.malaria,
                          color: ProgramColors.malaria,
                          onTap: () => setState(() => _filterProgram = HealthProgram.malaria),
                        ),
                        const SizedBox(width: 8),
                        _ProgramFilterChip(
                          label: 'HIV',
                          selected: _filterProgram == HealthProgram.hiv,
                          color: ProgramColors.hiv,
                          onTap: () => setState(() => _filterProgram = HealthProgram.hiv),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (role == UserRole.fieldProvider) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isViewOnly
                                ? null
                                : () => showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      showDragHandle: true,
                                      builder: (_) => _AddProductToFacilitySheet(userId: userId),
                                    ),
                            icon: Icon(Icons.playlist_add, color: Theme.of(context).colorScheme.primary),
                            label: const Text('Add Product'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isViewOnly
                                ? null
                                : () => showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      showDragHandle: true,
                                      builder: (_) => _RequestNewProductSheet(userId: userId),
                                    ),
                            icon: Icon(Icons.campaign, color: Theme.of(context).colorScheme.primary),
                            label: const Text('Request New'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isViewOnly
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('View-only access: restock requests are disabled.')),
                              );
                            }
                          : () => context.push('/stock-requests/new'),
                      icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
                      label: const Text('Request Restock'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => inventory.initialize(),
                child: filtered.isEmpty && role == UserRole.fieldProvider
                    ? ListView(
                        padding: AppSpacing.paddingLg,
                        children: [
                          const SizedBox(height: 32),
                          Icon(Icons.inventory_2, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No products found', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text('Try clearing filters or search, or pull-to-refresh to sync products.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                        ],
                      )
                    : ListView.separated(
                        padding: AppSpacing.paddingLg,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final commodity = filtered[index];
                          return _CommodityListCard(
                            commodity: commodity,
                            userId: userId,
                            canEditThreshold: canEditThresholds,
                            onTap: () => context.push('/inventory/${commodity.id}'),
                            onEditThreshold: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) => _SetMinThresholdSheet(userId: userId, commodity: commodity),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProviderBottomNav(currentIndex: 2, deliveryBadge: deliveryBadge),
    );
  }
}

class _AddProductToFacilitySheet extends StatefulWidget {
  final String userId;

  const _AddProductToFacilitySheet({required this.userId});

  @override
  State<_AddProductToFacilitySheet> createState() => _AddProductToFacilitySheetState();
}

class _AddProductToFacilitySheetState extends State<_AddProductToFacilitySheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final query = _searchCtrl.text.trim().toLowerCase();
    final available = inventory.commodities.where((c) => query.isEmpty || c.name.toLowerCase().contains(query)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receive stock', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Select an existing product, then enter the quantity you are receiving (plus batch/expiry if available). This will add to your current quantity.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search'),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: available.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No matching products.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: available.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = available[i];
                        final currentQty = inventory.getQuantityForUser(commodityId: c.id, userId: widget.userId);
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
                          title: Text(c.name, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          subtitle: Text('${c.program.name.toUpperCase()} • Current: ${inventory.formatQuantityForUser(userId: widget.userId, commodity: c, quantity: currentQty)}', style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          trailing: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
                          onTap: () async {
                            try {
                              await showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (_) => _ReceiveStockSheet(userId: widget.userId, commodity: c),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not receive stock.')));
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveStockSheet extends StatefulWidget {
  final String userId;
  final Commodity commodity;

  const _ReceiveStockSheet({required this.userId, required this.commodity});

  @override
  State<_ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

class _ReceiveStockSheetState extends State<_ReceiveStockSheet> {
  final _qtyCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  String? _unitOverride;
  DateTime? _expiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final inventory = context.read<InventoryService>();
    _batchCtrl.text = inventory.getBatchNumberForUser(userId: widget.userId, commodityId: widget.commodity.id) ?? '';
    _expiry = inventory.getExpiryDateForUser(userId: widget.userId, commodityId: widget.commodity.id);
    _unitOverride = inventory.getUnitOverrideForUser(userId: widget.userId, commodityId: widget.commodity.id);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final now = DateTime.now();
    final currentQty = inventory.getQuantityForUser(commodityId: widget.commodity.id, userId: widget.userId);
    final effectiveUnit = inventory.getEffectiveUnitOfExpressionForUser(userId: widget.userId, commodity: widget.commodity);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receive ${widget.commodity.name}', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Current: ${inventory.formatQuantityForUser(userId: widget.userId, commodity: widget.commodity, quantity: currentQty, showNotSet: true)}', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Quantity received', prefixIcon: Icon(Icons.numbers)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: UnitOfExpression.normalize(_unitOverride),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                ...UnitOfExpression.allowed.map((u) => DropdownMenuItem<String?>(value: u, child: Text(u))),
              ],
              onChanged: (v) => setState(() => _unitOverride = v),
              decoration: InputDecoration(
                labelText: 'Unit of expression',
                helperText: effectiveUnit == null ? 'Not set yet' : 'Current: $effectiveUnit',
                prefixIcon: const Icon(Icons.straighten),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batchCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Batch number', prefixIcon: Icon(Icons.confirmation_number)),
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
                decoration: const InputDecoration(labelText: 'Expiry date'),
                child: Text(_expiry == null ? 'Select a date' : _formatDate(_expiry!)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final qty = int.tryParse(_qtyCtrl.text.trim());
                        if (qty == null || qty <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid quantity (greater than 0).')));
                          return;
                        }

                        final batch = _batchCtrl.text.trim();
                        if (batch.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch number is required.')));
                          return;
                        }

                        if (_expiry == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expiry date is required.')));
                          return;
                        }

                        final expiry = DateTime(_expiry!.year, _expiry!.month, _expiry!.day);
                        final today = DateTime(now.year, now.month, now.day);
                        if (expiry.isBefore(today)) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expiry date cannot be in the past.')));
                          return;
                        }

                        setState(() => _saving = true);
                        try {
                          final newQty = await inventory.receiveStockForCurrentFieldProvider(
                            commodityId: widget.commodity.id,
                            quantityReceived: qty,
                            expiryDate: expiry,
                            batchNumber: batch,
                            unitOverride: _unitOverride,
                          );
                          await inventory.initialize();
                          if (!context.mounted) return;
                          context.pop();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added $qty to ${widget.commodity.name}. New total: $newQty.')));
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save stock update: $e')));
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add to stock'),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _EditBatchExpirySheet extends StatefulWidget {
  final String userId;
  final Commodity commodity;
  final bool isNewAssignment;

  const _EditBatchExpirySheet({required this.userId, required this.commodity, required this.isNewAssignment});

  @override
  State<_EditBatchExpirySheet> createState() => _EditBatchExpirySheetState();
}

class _EditBatchExpirySheetState extends State<_EditBatchExpirySheet> {
  final _batchCtrl = TextEditingController();
  DateTime? _expiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final inventory = context.read<InventoryService>();
    _batchCtrl.text = inventory.getBatchNumberForUser(userId: widget.userId, commodityId: widget.commodity.id) ?? '';
    _expiry = inventory.getExpiryDateForUser(userId: widget.userId, commodityId: widget.commodity.id);
  }

  @override
  void dispose() {
    _batchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
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
            Text('Batch & expiry', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(widget.isNewAssignment ? 'Optional: add batch and expiry details for this product in your facility.' : 'Update batch and expiry details for this product in your facility.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: _batchCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Batch Number (optional)'),
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
                child: Text(_expiry == null ? 'Not set' : _formatDate(_expiry!)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => context.pop(),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final expiry = _expiry == null ? null : DateTime(_expiry!.year, _expiry!.month, _expiry!.day);
                            if (widget.isNewAssignment && expiry != null) {
                              final today = DateTime(now.year, now.month, now.day);
                              if (expiry.isBefore(today)) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expiry date cannot be in the past for a newly added product.')));
                                return;
                              }
                            }

                            setState(() => _saving = true);
                            try {
                              await inventory.setBatchExpiryForUser(
                                userId: widget.userId,
                                commodityId: widget.commodity.id,
                                batchNumber: _batchCtrl.text.trim(),
                                expiryDate: expiry,
                              );
                              if (!context.mounted) return;
                              context.pop();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
                            } catch (e) {
                              debugPrint('Batch/expiry save failed: $e');
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
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
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _RequestNewProductSheet extends StatefulWidget {
  final String userId;

  const _RequestNewProductSheet({required this.userId});

  @override
  State<_RequestNewProductSheet> createState() => _RequestNewProductSheetState();
}

class _RequestNewProductSheetState extends State<_RequestNewProductSheet> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  HealthProgram? _program;
  String? _unit;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final auth = context.watch<AuthService>();
    final facilityName = auth.currentUser?.facilityName;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request new product', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Send a request to Super Admin to add this product to the master list.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Product name')), 
            const SizedBox(height: 12),
            DropdownButtonFormField<HealthProgram>(
              value: _program,
              items: const [
                DropdownMenuItem(value: HealthProgram.malaria, child: Text('Malaria')),
                DropdownMenuItem(value: HealthProgram.hiv, child: Text('HIV')),
              ],
              onChanged: (v) => setState(() => _program = v),
              decoration: const InputDecoration(labelText: 'Program (optional)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _unit,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                ...UnitOfExpression.allowed.map((u) => DropdownMenuItem<String?>(value: u, child: Text(u))),
              ],
              onChanged: (v) => setState(() => _unit = v),
              decoration: const InputDecoration(labelText: 'Unit of expression (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _notesCtrl, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting
                    ? null
                    : () async {
                        final name = _nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a product name.')));
                          return;
                        }
                        setState(() => _submitting = true);
                        try {
                          await inventory.requestNewProduct(
                            userId: widget.userId,
                            requestedName: name,
                            unit: _unit,
                            program: _program,
                            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
                            facilityName: facilityName,
                          );
                          if (!context.mounted) return;
                          context.pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request submitted.')));
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit request (check connectivity / backend table).')));
                        } finally {
                          if (mounted) setState(() => _submitting = false);
                        }
                      },
                icon: const Icon(Icons.send, color: Colors.white),
                label: const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgramFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _ProgramFilterChip({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = color ?? scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? base.withValues(alpha: 0.12) : scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: selected ? base.withValues(alpha: 0.5) : scheme.outline.withValues(alpha: 0.25), width: 1),
        ),
        child: Text(label, style: context.textStyles.labelLarge?.copyWith(color: selected ? base : scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _CommodityListCard extends StatelessWidget {
  final Commodity commodity;
  final String userId;
  final bool canEditThreshold;
  final VoidCallback onTap;
  final VoidCallback onEditThreshold;

  const _CommodityListCard({required this.commodity, required this.userId, required this.canEditThreshold, required this.onTap, required this.onEditThreshold});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final qtyLabel = inventory.formatQuantityForUser(userId: userId, commodity: commodity, quantity: commodity.currentQuantity);
    final minLabel = 'Min: ${inventory.formatQuantityForUser(userId: userId, commodity: commodity, quantity: commodity.minThreshold)}';
    final expiry = inventory.getExpiryDateForUser(userId: userId, commodityId: commodity.id);
    final expiryLabel = expiry == null
        ? 'Expiry: Not set'
        : 'Expiry: ${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.medical_services, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(commodity.name, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ProgramBadge(program: commodity.program),
                      const SizedBox(width: 10),
                      Text(qtyLabel, style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(minLabel, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(expiryLabel, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StockStatusBadge(status: commodity.status),
                if (canEditThreshold) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: onEditThreshold,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('Set minimum', style: context.textStyles.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SetMinThresholdSheet extends StatefulWidget {
  final String userId;
  final Commodity commodity;

  const _SetMinThresholdSheet({required this.userId, required this.commodity});

  @override
  State<_SetMinThresholdSheet> createState() => _SetMinThresholdSheetState();
}

class _SetMinThresholdSheetState extends State<_SetMinThresholdSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final inventory = context.read<InventoryService>();
    final current = inventory.getMinThresholdForUser(userId: widget.userId, commodity: widget.commodity);
    _ctrl = TextEditingController(text: current.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryService>();
    final current = inventory.getMinThresholdForUser(userId: widget.userId, commodity: widget.commodity);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + MediaQuery.of(context).viewInsets.bottom, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Minimum threshold', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('${widget.commodity.name} • Current minimum: $current', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Set new minimum', prefixIcon: Icon(Icons.numbers)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final raw = _ctrl.text.trim();
                        final parsed = int.tryParse(raw);
                        if (parsed == null || parsed < 0) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid non-negative number.')));
                          return;
                        }
                        setState(() => _saving = true);
                        try {
                          await inventory.setMinThresholdForUser(userId: widget.userId, commodityId: widget.commodity.id, minThreshold: parsed);
                          if (!context.mounted) return;
                          context.pop();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minimum threshold updated.')));
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update threshold.')));
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: _saving
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                    : const Text('Save'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
