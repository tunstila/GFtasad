import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/stock_request.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/services/fieldprovider_analytics_service.dart';
import 'package:mediflow/services/superadmin_analytics_service.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/utils/csv_downloader.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:mediflow/widgets/metric_card.dart';
import 'package:mediflow/widgets/date_range_filter_bar.dart';
import 'package:provider/provider.dart';

/// Read-only analytics dashboard for admin roles (State/National/SFH).
///
/// Super Admins can also access this, but they additionally have Users & Approvals.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _refreshing = false;
  bool _startedRealtime = false;
  bool _exportingAllTestsCsv = false;

  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)), end: DateTime(now.year, now.month, now.day, 23, 59, 59));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAllowed();
      _bootstrapAdminRealtime();
      _kickoffIdBackfill();
    });
  }

  Future<void> _kickoffIdBackfill() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    if (user.role != UserRole.admin && user.role != UserRole.superAdmin) return;
    try {
      // Best-effort: ensures existing FieldProviders/Clients have IDs.
      await SupabaseConfig.client.functions.invoke('id_management', body: const {'action': 'backfill_all'});
    } catch (e) {
      debugPrint('ID backfill failed (non-fatal): $e');
    }
  }

  bool _inRange(DateTime d) {
    final local = d.toLocal();
    final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final end = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59);
    return (local.isAtSameMomentAs(start) || local.isAfter(start)) && (local.isAtSameMomentAs(end) || local.isBefore(end));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = DateTimeRange(start: picked.start, end: picked.end));
  }

  @override
  void dispose() {
    _stopAdminRealtime();
    super.dispose();
  }

  void _ensureAllowed() {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }
    if (!user.hasGlobalView) {
      context.go('/provider-home');
    }
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    setState(() => _refreshing = true);
    try {
      // Keep backend-driven tiles consistent after refresh.
      context.read<FieldProviderAnalyticsService>().invalidate();
      await Future.wait([
        context.read<TestRecordService>().syncAllForAdmin(),
        context.read<InventoryService>().syncAllForAdmin(),
        context.read<DeliveryService>().syncAllForAdmin(),
        context.read<StockRequestService>().loadAllForAdmin(),
        // Users summary is loaded via AuthService on-demand.
      ]);
    } catch (e) {
      debugPrint('Admin dashboard refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _bootstrapAdminRealtime() async {
    if (_startedRealtime) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null || !user.hasGlobalView) return;

    _startedRealtime = true;

    // Ensure we have at least one initial snapshot, then realtime keeps it fresh.
    try {
      await Future.wait([
        context.read<TestRecordService>().syncAllForAdmin(),
        context.read<InventoryService>().syncAllForAdmin(),
        context.read<DeliveryService>().syncAllForAdmin(),
        context.read<StockRequestService>().loadAllForAdmin(),
      ]);
    } catch (e) {
      debugPrint('Admin initial sync failed (continuing): $e');
    }

    await Future.wait([
      context.read<TestRecordService>().startRealtime(forAdmin: true, userId: user.id),
      context.read<InventoryService>().startRealtime(forAdmin: true, userId: user.id),
      context.read<DeliveryService>().startRealtime(forAdmin: true, providerId: user.id),
      context.read<StockRequestService>().startRealtimeForAdmin(),
    ]);
  }

  void _stopAdminRealtime() {
    if (!_startedRealtime) return;
    _startedRealtime = false;
    try {
      context.read<TestRecordService>().stopRealtime();
      context.read<InventoryService>().stopRealtime();
      context.read<DeliveryService>().stopRealtime();
      context.read<StockRequestService>().stopRealtime();
    } catch (_) {
      // ignore (dispose can run during tree teardown)
    }
  }

  int _onlineUsersEstimate(List<User> users) {
    // Presence requires a dedicated heartbeat column; until then we estimate “online”
    // by users active within the last 15 minutes.
    final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
    return users.where((u) {
      final ts = u.lastLogin ?? u.updatedAt;
      return ts.isAfter(cutoff);
    }).length;
  }

  Future<void> _downloadAllTestRecordsCsv() async {
    final auth = context.read<AuthService>();
    if (!auth.isSuperAdminFull || _exportingAllTestsCsv) return;

    setState(() => _exportingAllTestsCsv = true);
    try {
      final res = await SupabaseConfig.client.functions.invoke('export_all_test_records_csv');
      final data = res.data;
      if (data is! Map) throw Exception('Unexpected export response');
      final filename = (data['filename'] ?? 'all_test_records.csv').toString();
      final csv = (data['csv'] ?? '').toString();
      if (csv.trim().isEmpty) throw Exception('Export returned an empty CSV');

      final savedPath = await downloadCsv(filename: filename, csvUtf8: csv);
      if (!mounted) return;

      final rowCount = data['rowCount'];
      final msg = savedPath == null
          ? 'Downloaded ${rowCount ?? ''} rows.'
          : 'Saved ${rowCount ?? ''} rows to: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint('Export all test records CSV failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _exportingAllTestsCsv = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final scheme = Theme.of(context).colorScheme;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final testSvc = context.watch<TestRecordService>();
    final invSvc = context.watch<InventoryService>();
    final delSvc = context.watch<DeliveryService>();
    final reqSvc = context.watch<StockRequestService>();
    final fpAnalytics = context.watch<FieldProviderAnalyticsService>();

    // Date-range aggregates (client-side). This keeps the UI functional even
    // before you deploy optional RPC/view optimizations.
    final testsInRange = testSvc.records.where((r) => _inRange(r.testDate)).toList();
    final byProgram = <String, int>{};
    for (final r in testsInRange) {
      byProgram[r.program.name] = (byProgram[r.program.name] ?? 0) + 1;
    }
    final totalTests = testsInRange.length;

    final movementsInRange = invSvc.movements.where((m) => _inRange(m.createdAt)).toList();
    final movementsCount = movementsInRange.length;

    final requestsInRange = reqSvc.allRequests.where((r) => _inRange(r.createdAt)).toList();
    final pendingStockRequests = requestsInRange.where((r) => r.status == StockRequestStatus.pending).length;

    final deliveriesInRange = delSvc.deliveries.where((d) => _inRange(d.deliveryDate)).toList();
    final pendingDeliveries = deliveriesInRange.where((d) => d.status.name == 'pending').length;
    final acceptedDeliveries = deliveriesInRange.where((d) => d.status.name == 'accepted').length;

    final stockAlerts = invSvc.getStockAlertCountAll();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Analytics'),
        actions: [
          if (auth.isSuperAdminFull)
            TextButton.icon(
              onPressed: () => context.push('/admin/users'),
              icon: Icon(Icons.people_alt_outlined, color: scheme.primary),
              label: Text('Users', style: TextStyle(color: scheme.primary)),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _refreshAll,
            icon: _refreshing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  )
                : const Icon(Icons.refresh),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome,', style: context.textStyles.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(user.username, style: context.textStyles.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  _roleLabel(user),
                  style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),

                if (auth.isSuperAdminFull) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exportingAllTestsCsv ? null : _downloadAllTestRecordsCsv,
                      icon: _exportingAllTestsCsv
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                          : Icon(Icons.download_outlined, color: scheme.onPrimary),
                      label: Text('Download All Test Records CSV', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/admin/login-tracker'),
                      icon: Icon(Icons.history_rounded, color: scheme.primary),
                      label: Text('Login Tracker', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                DateRangeFilterBar(range: _range, onPick: _pickRange),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<int?>(
                        future: testSvc.fetchLifetimeTotalCount(),
                        builder: (context, snap) {
                          final v = snap.data;
                          return MetricCard(
                            title: 'Lifetime Tests',
                            value: v == null ? '—' : '$v',
                            icon: Icons.all_inbox_outlined,
                            onTap: () => context.push('/test-records'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Tests (Range)',
                        value: '$totalTests',
                        icon: Icons.task_alt,
                        onTap: () => _openTodayTestsBreakdown(context, byProgram),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Stock Alerts',
                        value: '$stockAlerts',
                        icon: Icons.warning_amber_rounded,
                        color: stockAlerts > 0 ? AlertColors.warning : null,
                        onTap: () => _openStockAlertsSheet(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Pending Deliveries',
                        value: '$pendingDeliveries',
                        icon: Icons.local_shipping_outlined,
                        color: pendingDeliveries > 0 ? AlertColors.info : null,
                        onTap: () => context.push('/deliveries'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Stock Requests',
                        value: '$pendingStockRequests',
                        icon: Icons.inventory_2_outlined,
                        color: pendingStockRequests > 0 ? AlertColors.info : null,
                        onTap: () => _openStockRequestsSummary(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Accepted Deliveries',
                        value: '$acceptedDeliveries',
                        icon: Icons.check_circle_outline,
                        onTap: () => context.push('/deliveries'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Inventory Updates (Today)',
                        value: '$movementsCount',
                        icon: Icons.swap_vert,
                        onTap: () => context.push('/inventory'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder<int>(
                        future: fpAnalytics.fetchTotal(),
                        builder: (context, snap) {
                          final v = snap.data;
                          final hasErr = snap.hasError || fpAnalytics.lastError != null;
                          return MetricCard(
                            title: 'Field Providers',
                            value: hasErr ? '—' : (v == null ? '—' : '$v'),
                            icon: Icons.person_pin_circle_outlined,
                            onTap: () {
                              if (hasErr) {
                                _openFieldProviderTileError(context, fpAnalytics.lastError ?? snap.error);
                                return;
                              }
                              context.push('/admin/analytics/fieldproviders');
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),

                if (auth.isSuperAdminFull) ...[
                  const SizedBox(height: 12),
                  FutureBuilder<EnrollmentCounts>(
                    future: SuperAdminAnalyticsService.fetchEnrollmentCounts(),
                    builder: (context, snap) {
                      final hasErr = snap.hasError;
                      final data = snap.data;
                      return Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Enrolled PPMVs',
                              value: hasErr || data == null ? '—' : '${data.ppmv}',
                              icon: Icons.storefront_outlined,
                              onTap: () => context.push('/admin/enrollment?providerType=ppmv'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Enrolled CPs',
                              value: hasErr || data == null ? '—' : '${data.cp}',
                              icon: Icons.local_hospital_outlined,
                              onTap: () => context.push('/admin/enrollment?providerType=cp'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  MetricCard(
                    title: 'Cumulative Test Records',
                    value: 'View',
                    icon: Icons.fact_check_outlined,
                    onTap: () => context.push('/admin/test-records-analytics'),
                  ),
                ],

                const SizedBox(height: 12),
                StreamBuilder<List<User>>(
                  stream: auth.streamAllUsersForAdmin(),
                  builder: (context, snap) {
                    final users = snap.data ?? const <User>[];
                    final online = users.isEmpty ? null : _onlineUsersEstimate(users);
                    return Row(
                      children: [
                        Expanded(
                          child: MetricCard(
                            title: 'Online Users',
                            value: online == null ? '—' : '$online',
                            icon: Icons.wifi_tethering,
                            onTap: () => _openUserAggregates(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricCard(
                            title: 'Users Summary',
                            value: users.isEmpty ? '—' : '${users.length}',
                            icon: Icons.groups_2_outlined,
                            onTap: () => _openUserAggregates(context),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),
                Text('Tests by Program (Range)', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _ProgramRow(program: HealthProgram.malaria, count: byProgram[HealthProgram.malaria.name] ?? 0),
                const SizedBox(height: 10),
                _ProgramRow(program: HealthProgram.hiv, count: byProgram[HealthProgram.hiv.name] ?? 0),

                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Admin roles are read-only: you can view system aggregates and drill down, but only Super Admin can approve or create users.',
                          style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _roleLabel(User user) {
    if (user.hasSuperAdminFull) return 'Super Admin';
    return switch (user.role) {
      UserRole.stateMalaria => '${user.state ?? 'State'} SMEP (Admin view)',
      UserRole.stateHIVTB => '${user.state ?? 'State'} SASCP (Admin view)',
      UserRole.nationalMalaria => 'NMEP (Admin view)',
      UserRole.nationalHIVTB => 'NASCP (Admin view)',
      UserRole.sfhTeam => 'SFH (Admin view)',
      _ => user.role.name,
    };
  }

  void _openStockRequestsSummary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final req = context.read<StockRequestService>();
    final total = req.getTotalCountAll();
    final pending = req.getPendingCountAll();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock Requests', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _KeyValueRow(label: 'Pending', value: '$pending'),
              _KeyValueRow(label: 'Total', value: '$total'),
              const SizedBox(height: 12),
              Text(
                'This is an aggregated snapshot across all field providers and suppliers (based on your RLS visibility).',
                style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUserAggregates(BuildContext context) async {
    final auth = context.read<AuthService>();
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
          child: FutureBuilder<UserAggregates>(
            future: auth.fetchUserAggregates(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return SizedBox(
                  height: 220,
                  child: Center(
                    child: Text('Failed to load user aggregates. ${snap.error}', textAlign: TextAlign.center),
                  ),
                );
              }

              final data = snap.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Users Summary', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _KeyValueRow(label: 'Total users', value: '${data.total}'),
                  const SizedBox(height: 10),
                  Text('By Role', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ...data.byRole.entries.map((e) {
                    final roleKey = e.key;
                    final isFieldProvider = roleKey == 'fieldProvider' || roleKey == 'field_provider';
                    if (!isFieldProvider) return _KeyValueRow(label: roleKey, value: '${e.value}');

                    return _ClickableKeyValueRow(
                      label: roleKey,
                      value: '${e.value}',
                      hint: 'View Field Provider analytics',
                      onTap: () {
                        context.pop();
                        context.push('/admin/analytics/fieldproviders');
                      },
                    );
                  }),
                  const SizedBox(height: 10),
                  Text('By State', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ...data.byState.entries.map(
                    (e) => _ClickableKeyValueRow(
                      label: e.key,
                      value: '${e.value}',
                      hint: 'Filter Field Providers by state',
                      onTap: () {
                        context.pop();
                        final encoded = Uri.encodeQueryComponent(e.key);
                        context.push('/admin/analytics/fieldproviders?state=$encoded');
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),
        );
      },
    );
  }
  void _openTodayTestsBreakdown(BuildContext context, Map<String, int> counts) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tests breakdown', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _KeyValueRow(label: 'Malaria', value: '${counts[HealthProgram.malaria.name] ?? 0}'),
              _KeyValueRow(label: 'HIV', value: '${counts[HealthProgram.hiv.name] ?? 0}'),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _openStockAlertsSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inv = context.read<InventoryService>();
    final alerts = inv.getStockAlertsAll();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock alerts', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Items below minimum threshold (system-wide).', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (alerts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text('No alerts right now.', style: context.textStyles.bodyMedium),
                )
              else
                ...alerts.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AlertColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                  'Qty: ${c.currentQuantity} (min: ${c.minThreshold})',
                                  style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _openFieldProviderTileError(BuildContext context, Object? error) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Field Provider tile unavailable', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                'This tile uses backend RPCs (e.g. get_fieldprovider_total). If they are not deployed yet (or RLS blocks access), the count cannot load.',
                style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 10),
              Text('Debug details:', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                (error ?? 'Unknown error').toString(),
                style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                'Fix: apply the SQL in lib/supabase/supabase_tables.sql to your Supabase project, then refresh this dashboard.',
                style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _ClickableKeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final VoidCallback onTap;

  const _ClickableKeyValueRow({required this.label, required this.value, required this.onTap, this.hint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint!, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.2)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(value, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgramRow extends StatelessWidget {
  final HealthProgram program;
  final int count;

  const _ProgramRow({required this.program, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (program) {
      HealthProgram.malaria => ProgramColors.malaria,
      HealthProgram.hiv => ProgramColors.hiv,
      HealthProgram.tb => ProgramColors.tb,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(program.name.toUpperCase(), style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
          Text('$count', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          Text(value, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
