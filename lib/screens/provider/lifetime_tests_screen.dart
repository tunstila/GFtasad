import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class LifetimeTestsScreen extends StatefulWidget {
  const LifetimeTestsScreen({super.key});

  @override
  State<LifetimeTestsScreen> createState() => _LifetimeTestsScreenState();
}

class _LifetimeTestsScreenState extends State<LifetimeTestsScreen> {
  final _searchCtrl = TextEditingController();

  DateTime? _startDay;
  DateTime? _endDay;
  DateTimeRange? _activeRange;

  Future<List<TestRecord>>? _remoteFuture;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _remoteFuture ??= _fetch();
  }

  Future<List<TestRecord>> _fetch() {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final userId = user?.id ?? '';
    return context.read<TestRecordService>().fetchAllVisibleRecordsRemote(userId: userId, dateRange: _activeRange);
  }

  Future<void> _refresh() async {
    setState(() => _remoteFuture = _fetch());
    await _remoteFuture;
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDate: _startDay ?? _activeRange?.start ?? DateTime(now.year, now.month, now.day),
      helpText: 'Start date',
    );
    if (picked == null) return;
    setState(() => _startDay = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDate: _endDay ?? _activeRange?.end ?? DateTime(now.year, now.month, now.day),
      helpText: 'End date',
    );
    if (picked == null) return;
    setState(() => _endDay = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _applyFilter() async {
    final start = _startDay;
    final end = _endDay;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select both start and end dates.')));
      return;
    }
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date must be on/after start date.')));
      return;
    }
    setState(() {
      _activeRange = DateTimeRange(start: start, end: end);
      _remoteFuture = _fetch();
    });
    await _remoteFuture;
  }

  Future<void> _clearFilter() async {
    setState(() {
      _startDay = null;
      _endDay = null;
      _activeRange = null;
      _remoteFuture = _fetch();
    });
    await _remoteFuture;
  }

  String _fmtDay(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lifetime Tests'),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.horizontalLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  _LifetimeFiltersCard(
                    startDay: _startDay,
                    endDay: _endDay,
                    activeRange: _activeRange,
                    fmtDay: _fmtDay,
                    onPickStart: _pickStart,
                    onPickEnd: _pickEnd,
                    onApply: _applyFilter,
                    onClear: _clearFilter,
                  ),
                  const SizedBox(height: 12),
                  _SearchField(controller: _searchCtrl, onChanged: () => setState(() {})),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<TestRecord>>(
                  future: _remoteFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return ListView(
                        padding: AppSpacing.paddingLg,
                        children: [
                          const SizedBox(height: 40),
                          Icon(Icons.error_outline, size: 44, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Center(child: Text('Failed to load test records.', style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                          const SizedBox(height: 10),
                          Center(child: Text('${snap.error}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton.icon(
                              onPressed: _refresh,
                              icon: Icon(Icons.refresh, color: scheme.primary),
                              label: const Text('Retry'),
                            ),
                          ),
                        ],
                      );
                    }

                    final query = _searchCtrl.text.trim().toLowerCase();
                    var records = (snap.data ?? const <TestRecord>[]).toList();
                    records.retainWhere((r) => r.program != HealthProgram.tb);

                    if (query.isNotEmpty) {
                      records = records.where((r) {
                        final hay = '${r.clientName} ${r.clientId} ${r.program.name} ${r.visitType.name} ${r.sex}'.toLowerCase();
                        return hay.contains(query);
                      }).toList();
                    }

                    records.sort((a, b) => b.testDate.compareTo(a.testDate));

                    final emptyText = _activeRange == null ? 'No tests recorded yet.' : 'No tests match the selected date range.';

                    return ListView(
                      key: const PageStorageKey('lifetime-tests-list'),
                      padding: AppSpacing.paddingLg,
                      children: [
                        Row(
                          children: [
                            Text('${records.length} test(s)', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                            const Spacer(),
                            if (_activeRange != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(AppRadius.xl),
                                  border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                                ),
                                child: Text('${_fmtDay(_activeRange!.start)} → ${_fmtDay(_activeRange!.end)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (records.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 44),
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long, size: 44, color: scheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(emptyText, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          )
                        else
                          ...records.map((r) => _LifetimeTestRow(record: r)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LifetimeFiltersCard extends StatelessWidget {
  final DateTime? startDay;
  final DateTime? endDay;
  final DateTimeRange? activeRange;
  final String Function(DateTime) fmtDay;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _LifetimeFiltersCard({
    required this.startDay,
    required this.endDay,
    required this.activeRange,
    required this.fmtDay,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = activeRange != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.date_range, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Date range filter', style: context.textStyles.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(isActive ? '${fmtDay(activeRange!.start)} → ${fmtDay(activeRange!.end)}' : 'All time', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              if (isActive)
                TextButton(
                  onPressed: onClear,
                  child: Text('Clear', style: context.textStyles.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DatePickPill(
                  label: 'Start',
                  value: startDay == null ? 'Select' : fmtDay(startDay!),
                  onTap: onPickStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DatePickPill(
                  label: 'End',
                  value: endDay == null ? 'Select' : fmtDay(endDay!),
                  onTap: onPickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApply,
                  icon: Icon(Icons.filter_alt, color: scheme.onPrimary),
                  label: Text('Apply', style: context.textStyles.labelLarge?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DatePickPill extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DatePickPill({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: scheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(value, style: context.textStyles.labelLarge?.copyWith(fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by client name, ID, program…',
        prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _LifetimeTestRow extends StatelessWidget {
  final TestRecord record;

  const _LifetimeTestRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (record.syncStatus) {
      SyncStatus.synced => SyncColors.synced,
      SyncStatus.pending => SyncColors.pending,
      SyncStatus.syncing => SyncColors.syncing,
      SyncStatus.failed => SyncColors.failed,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/test-records/${record.id}'),
        splashFactory: NoSplash.splashFactory,
        highlightColor: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.task_alt, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.clientName, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      '${record.clientId} • ${record.program.name.toUpperCase()} • ${_formatDateTime(record.testDate)}',
                      style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }
}
