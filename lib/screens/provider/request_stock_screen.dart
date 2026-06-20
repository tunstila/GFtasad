import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class RequestStockScreen extends StatefulWidget {
  const RequestStockScreen({super.key});

  @override
  State<RequestStockScreen> createState() => _RequestStockScreenState();
}

class _RequestStockScreenState extends State<RequestStockScreen> {
  int _step = 0;
  bool _loadingSuppliers = true;
  String _supplierQuery = '';
  List<User> _suppliers = const [];
  User? _selectedSupplier;

  String _itemQuery = '';
  String? _selectedCommodityId;
  int _quantityRequested = 0;
  String? _unitOfExpression;
  bool _submitting = false;

  String _notes = '';

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _loadingSuppliers = true);
    try {
      final service = context.read<StockRequestService>();
      final suppliers = await service.fetchSuppliers();
      if (!mounted) return;
      setState(() => _suppliers = suppliers);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load suppliers: $e')));
    } finally {
      if (mounted) setState(() => _loadingSuppliers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inventory = context.watch<InventoryService>();
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    final role = user?.role ?? UserRole.fieldProvider;
    final userId = user?.id ?? '';

    final filteredSuppliers = _suppliers.where((s) {
      if (_supplierQuery.trim().isEmpty) return true;
      final q = _supplierQuery.toLowerCase();
      return s.username.toLowerCase().contains(q) || s.email.toLowerCase().contains(q) || (s.facilityName ?? '').toLowerCase().contains(q);
    }).toList();

    final commodities = role == UserRole.fieldProvider ? inventory.getFacilityCommodities(userId) : inventory.commodities;
    final filteredCommodities = commodities.where((c) {
      if (_itemQuery.trim().isEmpty) return true;
      final q = _itemQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) || c.program.name.toLowerCase().contains(q);
    }).toList();

    final selectedCommodity = _selectedCommodityId == null ? null : commodities.where((c) => c.id == _selectedCommodityId).firstOrNull;

    // Prefill unit from product if available.
    final suggestedUnit = selectedCommodity?.normalizedUnitOfExpression;
    if (_step == 1 && _unitOfExpression == null && suggestedUnit != null) {
      _unitOfExpression = suggestedUnit;
    }

    return Scaffold(
      appBar: AppBar(
          title: const Text('Request Restock'),
          actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.paddingLg,
              child: _StepHeader(step: _step, supplier: _selectedSupplier),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: switch (_step) {
                  0 => _SupplierStep(
                      key: const ValueKey('supplier_step'),
                      loading: _loadingSuppliers,
                      suppliers: filteredSuppliers,
                      query: _supplierQuery,
                      onQueryChanged: (v) => setState(() => _supplierQuery = v),
                      selectedSupplierId: _selectedSupplier?.id,
                      onSelect: (s) => setState(() => _selectedSupplier = s),
                      emptyHint: 'No suppliers found. Ask an admin to create/approve supplier accounts.',
                    ),
                  _ => _SingleItemStep(
                      key: const ValueKey('items_step'),
                      commodities: filteredCommodities,
                      query: _itemQuery,
                      onQueryChanged: (v) => setState(() => _itemQuery = v),
                      notes: _notes,
                      onNotesChanged: (v) => setState(() => _notes = v),
                      selectedCommodityId: _selectedCommodityId,
                      onSelectCommodity: (id) {
                        setState(() {
                          _selectedCommodityId = id;
                          _unitOfExpression = null; // re-prefill from new product
                        });
                      },
                      quantityRequested: _quantityRequested,
                      onQuantityChanged: (qty) => setState(() => _quantityRequested = qty),
                      unitOfExpression: _unitOfExpression,
                      onUnitChanged: (u) => setState(() => _unitOfExpression = u),
                    ),
                },
              ),
            ),
            Container(
              padding: AppSpacing.paddingLg,
              decoration: BoxDecoration(color: scheme.surface, border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.16)))),
              child: Row(
                children: [
                  if (_step == 1)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : () => setState(() => _step = 0),
                        icon: Icon(Icons.chevron_left, color: scheme.primary),
                        label: Text('Suppliers', style: TextStyle(color: scheme.primary)),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (user == null || _submitting)
                          ? null
                          : () async {
                              if (_step == 0) {
                                if (_selectedSupplier == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a supplier to continue.')));
                                  return;
                                }
                                setState(() => _step = 1);
                                return;
                              }

                              final supplier = _selectedSupplier;
                              if (supplier == null) return;

                              final commodity = selectedCommodity;
                              if (commodity == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a product to continue.')));
                                return;
                              }

                              if (_quantityRequested <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity must be greater than zero.')));
                                return;
                              }

                              final unit = _unitOfExpression?.trim();
                              if (unit == null || unit.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a unit of expression.')));
                                return;
                              }

                              if ((user.businessAddress ?? '').trim().isEmpty || (user.state ?? '').trim().isEmpty || (user.lga ?? '').trim().isEmpty) {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Add your business address?'),
                                    content: const Text('Suppliers will need your address to deliver. Please update your business address now.'),
                                    actions: [
                                      TextButton(onPressed: () => context.pop(false), child: const Text('Later')),
                                      ElevatedButton(onPressed: () => context.pop(true), child: const Text('Update profile')),
                                    ],
                                  ),
                                );
                                if (ok == true && mounted) {
                                  context.push('/provider-profile/address');
                                  return;
                                }
                              }

                              setState(() => _submitting = true);
                              try {
                                final service = context.read<StockRequestService>();
                                final id = await service.createRestockRequest(
                                  supplierId: supplier.id,
                                  commodityId: commodity.id,
                                  quantityRequested: _quantityRequested,
                                  unitOfExpression: unit,
                                  notes: _notes,
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restock request sent to supplier')));
                                context.go('/stock-requests/$id');
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit request: $e')));
                              } finally {
                                if (mounted) setState(() => _submitting = false);
                              }
                            },
                      icon: Icon(
                        _step == 0 ? Icons.chevron_right : (_submitting ? Icons.hourglass_top : Icons.send),
                        color: Colors.white,
                      ),
                      label: Text(_step == 0 ? 'Next' : (_submitting ? 'Sending…' : 'Send request'), style: const TextStyle(color: Colors.white)),
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


class _StepHeader extends StatelessWidget {
  final int step;
  final User? supplier;

  const _StepHeader({required this.step, required this.supplier});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = step == 0 ? 'Choose a supplier' : 'Pick products & quantities';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.18))),
      child: Row(
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(step == 0 ? Icons.storefront : Icons.inventory_2, color: scheme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  step == 0
                      ? 'Select the supplier you want to request stock from.'
                      : 'Request only what you need. Supplier will see your address on the request.',
                  style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                if (step == 1 && supplier != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Supplier: ${supplier!.username}', style: context.textStyles.bodySmall?.copyWith(fontWeight: FontWeight.w800))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierStep extends StatelessWidget {
  final bool loading;
  final List<User> suppliers;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String? selectedSupplierId;
  final ValueChanged<User> onSelect;
  final String emptyHint;

  const _SupplierStep({
    super.key,
    required this.loading,
    required this.suppliers,
    required this.query,
    required this.onQueryChanged,
    required this.selectedSupplierId,
    required this.onSelect,
    required this.emptyHint,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: AppSpacing.paddingLg,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
              hintText: 'Search suppliers',
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
            ),
          ),
        ),
        Expanded(
          child: suppliers.isEmpty
              ? ListView(
                  padding: AppSpacing.paddingLg,
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.store_outlined, size: 44, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text('No suppliers available', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(emptyHint, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4), textAlign: TextAlign.center),
                  ],
                )
              : ListView.separated(
                  padding: AppSpacing.paddingLg,
                  itemCount: suppliers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final s = suppliers[index];
                    final selected = s.id == selectedSupplierId;
                    return InkWell(
                      onTap: () => onSelect(s),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.45) : scheme.outline.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(width: 46, height: 46, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: Icon(Icons.store, color: scheme.primary)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.displayName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 6),
                                  Text(s.facilityName ?? s.displayEmail, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (selected) Icon(Icons.check_circle, color: scheme.primary) else Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SingleItemStep extends StatelessWidget {
  final List<Commodity> commodities;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String notes;
  final ValueChanged<String> onNotesChanged;
  final String? selectedCommodityId;
  final ValueChanged<String> onSelectCommodity;
  final int quantityRequested;
  final ValueChanged<int> onQuantityChanged;
  final String? unitOfExpression;
  final ValueChanged<String> onUnitChanged;

  const _SingleItemStep({
    super.key,
    required this.commodities,
    required this.query,
    required this.onQueryChanged,
    required this.notes,
    required this.onNotesChanged,
    required this.selectedCommodityId,
    required this.onSelectCommodity,
    required this.quantityRequested,
    required this.onQuantityChanged,
    required this.unitOfExpression,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: AppSpacing.paddingLg,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
              hintText: 'Search products',
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            onChanged: onNotesChanged,
            maxLines: 2,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.note_alt_outlined, color: scheme.onSurfaceVariant),
              hintText: 'Optional notes (e.g. urgent, preferred delivery time)',
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.numbers, color: scheme.onSurfaceVariant),
                    hintText: 'Quantity requested',
                    filled: true,
                    fillColor: scheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                  ),
                  initialValue: quantityRequested == 0 ? '' : quantityRequested.toString(),
                  onChanged: (v) => onQuantityChanged(int.tryParse(v.trim()) ?? 0),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  value: unitOfExpression,
                  items: UnitOfExpression.allowed
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onUnitChanged(v);
                  },
                  decoration: InputDecoration(
                    hintText: 'Unit',
                    filled: true,
                    fillColor: scheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: commodities.isEmpty
              ? ListView(
                  padding: AppSpacing.paddingLg,
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.inventory_2_outlined, size: 44, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text('No products found', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Try adjusting your search, or pull-to-refresh Inventory to sync products.', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4), textAlign: TextAlign.center),
                  ],
                )
              : ListView.separated(
                  padding: AppSpacing.paddingLg,
                  itemCount: commodities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = commodities[index];
                    final selected = c.id == selectedCommodityId;
                    return InkWell(
                      onTap: () => onSelectCommodity(c.id),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.45) : scheme.outline.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(width: 44, height: 44, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.medical_services_outlined, color: scheme.primary)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'In stock: ${c.currentQuantity} • Min: ${c.minThreshold} • Unit: ${c.normalizedUnitOfExpression ?? 'Not set'}',
                                    style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (selected) Icon(Icons.check_circle, color: scheme.primary) else Icon(Icons.circle_outlined, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
