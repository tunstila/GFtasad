import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:mediflow/widgets/provider_bottom_nav.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class ManualStockAdjustmentScreen extends StatefulWidget {
  final String? preselectedCommodityId;

  const ManualStockAdjustmentScreen({super.key, this.preselectedCommodityId});

  @override
  State<ManualStockAdjustmentScreen> createState() => _ManualStockAdjustmentScreenState();
}

class _ManualStockAdjustmentScreenState extends State<ManualStockAdjustmentScreen> {
  String? _commodityId;
  MovementType _type = MovementType.add;
  final _qtyCtrl = TextEditingController();
  MovementReason _reason = MovementReason.countCorrection;
  final _notesCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  DateTime? _expiryDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _commodityId = widget.preselectedCommodityId;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _batchCtrl.dispose();
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
    final deliveryBadge = (role?.hasGlobalView ?? false)
        ? deliveryService.getPendingDeliveriesCountAll()
        : deliveryService.getPendingDeliveriesCount(userId);

    final commodities = inventory.commodities;
    final captureBatchExpiry = role == UserRole.supplier;

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Stock Adjustment'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(isOffline: false),
            Expanded(
              child: ListView(
                padding: AppSpacing.paddingLg,
                children: [
                  Text('Adjust stock levels with a reason code. Changes are recorded in movement history.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: _commodityId,
                    items: commodities.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (v) => setState(() => _commodityId = v),
                    decoration: const InputDecoration(labelText: 'Commodity'),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<MovementType>(
                    segments: const [
                      ButtonSegment(value: MovementType.add, label: Text('Add'), icon: Icon(Icons.add)),
                      ButtonSegment(value: MovementType.deduct, label: Text('Deduct'), icon: Icon(Icons.remove)),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<MovementReason>(
                    value: _reason,
                    items: const [
                      DropdownMenuItem(value: MovementReason.wastage, child: Text('Wastage')),
                      DropdownMenuItem(value: MovementReason.expiry, child: Text('Expiry')),
                      DropdownMenuItem(value: MovementReason.returnItem, child: Text('Return')),
                      DropdownMenuItem(value: MovementReason.countCorrection, child: Text('Count Correction')),
                      DropdownMenuItem(value: MovementReason.other, child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _reason = v ?? _reason),
                    decoration: const InputDecoration(labelText: 'Reason code'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  if (captureBatchExpiry) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _batchCtrl,
                      decoration: const InputDecoration(labelText: 'Batch number (required for supplier submissions)'),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final initial = _expiryDate ?? now.add(const Duration(days: 180));
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: initial,
                          firstDate: now.subtract(const Duration(days: 1)),
                          lastDate: now.add(const Duration(days: 3650)),
                          helpText: 'Select expiry date',
                        );
                        if (picked != null && mounted) setState(() => _expiryDate = picked);
                      },
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Expiry date (required for supplier submissions)'),
                        child: Text(_expiryDate == null ? 'Tap to select' : '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_submitting || isViewOnly)
                          ? null
                          : () async {
                              final qty = int.tryParse(_qtyCtrl.text.trim());
                              if (_commodityId == null || qty == null || qty <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select commodity and enter a valid quantity')));
                                return;
                              }

                              final commodity = commodities.firstWhere((c) => c.id == _commodityId);
                              final verb = _type == MovementType.add ? 'Add' : 'Deduct';
                              final u = inventory.getEffectiveUnitOfExpressionForUser(userId: userId, commodity: commodity);
                              final qtyLabel = u == null ? '$qty' : '$qty $u';

                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Confirm adjustment'),
                                  content: Text('$verb $qtyLabel for ${commodity.name}?'),
                                  actions: [
                                    TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => context.pop(true), child: const Text('Confirm')),
                                  ],
                                ),
                              );

                              if (confirmed != true) return;

                              setState(() => _submitting = true);
                              try {
                                if (captureBatchExpiry) {
                                  if (_batchCtrl.text.trim().isEmpty || _expiryDate == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch number and expiry date are required for supplier submissions.')));
                                    return;
                                  }
                                }
                                await inventory.adjustStock(
                                  commodityId: _commodityId!,
                                  type: _type,
                                  quantity: qty,
                                  reason: _reason,
                                  userId: userId,
                                  notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
                                  batchNumber: captureBatchExpiry ? _batchCtrl.text.trim() : null,
                                  expiryDate: captureBatchExpiry ? _expiryDate : null,
                                );
                                if (!context.mounted) return;
                                context.pop();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated')));
                              } finally {
                                if (mounted) setState(() => _submitting = false);
                              }
                            },
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: Text(isViewOnly ? 'View-only access' : 'Submit Adjustment'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ProviderBottomNav(currentIndex: 2, deliveryBadge: deliveryBadge),
    );
  }
}
