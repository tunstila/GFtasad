import 'package:flutter/material.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/date_range_filter_bar.dart';
import 'package:mediflow/widgets/metric_card.dart';
import 'package:mediflow/models/stock_request.dart';
import 'package:provider/provider.dart';

class NationalHivtbDashboardScreen extends StatefulWidget {
  const NationalHivtbDashboardScreen({super.key});

  @override
  State<NationalHivtbDashboardScreen> createState() => _NationalHivtbDashboardScreenState();
}

class _NationalHivtbDashboardScreenState extends State<NationalHivtbDashboardScreen> {
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)), end: DateTime(now.year, now.month, now.day, 23, 59, 59));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAllowed());
  }

  void _ensureAllowed() {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }
    if (user.role != UserRole.nationalHIVTB) {
      context.go(auth.homeRouteForCurrentUser());
    }
  }

  bool _inRange(DateTime d) {
    final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final end = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59);
    return (d.isAtSameMomentAs(start) || d.isAfter(start)) && (d.isAtSameMomentAs(end) || d.isBefore(end));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), initialDateRange: _range);
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final testSvc = context.watch<TestRecordService>();
    final invSvc = context.watch<InventoryService>();
    final delSvc = context.watch<DeliveryService>();
    final reqSvc = context.watch<StockRequestService>();

    final hivTests = testSvc.records.where((r) => r.program == HealthProgram.hiv && _inRange(r.testDate)).toList();

    final hivCount = hivTests.length;
    final hivCounselling = hivTests.where((r) => r.hivCounselling == true).length;

    final commodities = invSvc.commodities.where((c) => c.program == HealthProgram.hiv).toList();
    final alerts = commodities.where((c) => c.currentQuantity <= c.minThreshold).length;

    final requests = reqSvc.allRequests.where((r) {
      if (!_inRange(r.createdAt)) return false;
      return r.items.any((i) {
        final p = i.program.toLowerCase();
        return p == HealthProgram.hiv.name;
      });
    }).toList();
    final reqPending = requests.where((r) => r.status == StockRequestStatus.pending).length;

    final deliveries = delSvc.deliveries.where((d) {
      if (!_inRange(d.deliveryDate)) return false;
      return d.items.any((i) {
        final n = i.commodityName.toLowerCase();
        return n.contains('hiv');
      });
    }).toList();
    final inTransit = deliveries.where((d) => d.status.name == 'in_transit').length;
    final delivered = deliveries.where((d) => d.status.name == 'delivered' || d.status.name == 'accepted').length;

    return Scaffold(
      appBar: AppBar(title: const Text('National HIV Dashboard'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.paddingLg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome,', style: context.textStyles.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(user.username, style: context.textStyles.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            DateRangeFilterBar(range: _range, onPick: _pickRange),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: MetricCard(title: 'HIV tests', value: '$hivCount', icon: Icons.favorite_outline)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: MetricCard(title: 'HIV counselled', value: '$hivCounselling', icon: Icons.record_voice_over_outlined)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: MetricCard(title: 'Low-stock alerts', value: '$alerts', icon: Icons.inventory_2_outlined, color: alerts > 0 ? AlertColors.warning : null)),
              const SizedBox(width: 12),
              Expanded(child: MetricCard(title: 'Restock pending', value: '$reqPending', icon: Icons.request_quote_outlined)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: MetricCard(title: 'Deliveries in transit', value: '$inTransit', icon: Icons.local_shipping_outlined, color: inTransit > 0 ? AlertColors.info : null)),
              const SizedBox(width: 12),
              Expanded(child: MetricCard(title: 'Deliveries delivered', value: '$delivered', icon: Icons.check_circle_outline)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
              child: Text('Read-only access: you cannot record tests or modify inventory/requests.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
            ),
          ]),
        ),
      ),
    );
  }
}
