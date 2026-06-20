import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/program_badge.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:mediflow/widgets/date_range_filter_bar.dart';

class TestRecordsHistoryScreen extends StatefulWidget {
  final HealthProgram? initialProgram;
  final bool todayOnly;
  final DateTimeRange? initialDateRange;

  const TestRecordsHistoryScreen({super.key, this.initialProgram, this.todayOnly = false, this.initialDateRange});

  @override
  State<TestRecordsHistoryScreen> createState() => _TestRecordsHistoryScreenState();
}

class _TestRecordsHistoryScreenState extends State<TestRecordsHistoryScreen> {
  HealthProgram? _program;
  late DateTimeRange _range;

  Future<List<TestRecord>>? _remoteFuture;

  @override
  void initState() {
    super.initState();
    _program = widget.initialProgram;
    final now = DateTime.now();
    _range = widget.initialDateRange ?? DateTimeRange(start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)), end: DateTime(now.year, now.month, now.day));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.todayOnly) {
      final auth = context.read<AuthService>();
      final user = auth.currentUser;
      final scopedUserId = (user?.hasGlobalView ?? false) ? null : user?.id;
      _remoteFuture ??= context.read<TestRecordService>().fetchAllVisibleRecordsRemote(program: _program, userId: scopedUserId, dateRange: _range);
    }
  }

  Future<void> _refreshRemote() async {
    if (widget.todayOnly) return;
    final user = context.read<AuthService>().currentUser;
    final scopedUserId = (user?.hasGlobalView ?? false) ? null : user?.id;
    setState(() => _remoteFuture = context.read<TestRecordService>().fetchAllVisibleRecordsRemote(program: _program, userId: scopedUserId, dateRange: _range));
    await _remoteFuture;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
      helpText: 'Filter by date',
    );
    if (picked == null) return;

    setState(() {
      _range = DateTimeRange(start: DateTime(picked.start.year, picked.start.month, picked.start.day), end: DateTime(picked.end.year, picked.end.month, picked.end.day));
      if (!widget.todayOnly) {
        final user = context.read<AuthService>().currentUser;
        final scopedUserId = (user?.hasGlobalView ?? false) ? null : user?.id;
        _remoteFuture = context.read<TestRecordService>().fetchAllVisibleRecordsRemote(program: _program, userId: scopedUserId, dateRange: _range);
      }
    });
  }

  String _fmtDay(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final service = context.watch<TestRecordService>();

    final user = auth.currentUser;
    final hasGlobalView = user?.hasGlobalView ?? false;
    final userId = user?.id ?? '';

    // For all-time lists we use a canonical backend query so it always matches
    // the backend-scoped lifetime-count tile.
    // For "today" lists we keep the existing local-day logic unchanged.
    List<TestRecord> localRecords = hasGlobalView ? service.records : service.records.where((r) => r.userId == userId).toList();
    // TB is deprecated and should not be visible in any list.
    localRecords = localRecords.where((r) => r.program != HealthProgram.tb).toList();
    if (widget.todayOnly) {
      localRecords = hasGlobalView ? service.getTodayRecordsAll() : service.getTodayRecords(userId);
      localRecords = localRecords.where((r) => r.program != HealthProgram.tb).toList();
      if (_program != null) localRecords = localRecords.where((r) => r.program == _program).toList();
      localRecords.sort((a, b) => b.testDate.compareTo(a.testDate));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.todayOnly ? 'Today\'s Test Records' : 'Test Records'),
        actions: [
          IconButton(
            tooltip: 'Sync Status',
            onPressed: () => context.push('/sync-status'),
            icon: const Icon(Icons.cloud_sync),
          ),
          const AppAccountMenu(),
        ],
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
                  if (!widget.todayOnly) ...[
                    DateRangeFilterBar(range: _range, onPick: _pickRange),
                    const SizedBox(height: 12),
                  ],
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ProgramChip(
                          label: 'All',
                          selected: _program == null,
                          onTap: () {
                            setState(() {
                              _program = null;
                              if (!widget.todayOnly) {
                                final scopedUserId = hasGlobalView ? null : userId;
                                _remoteFuture = context.read<TestRecordService>().fetchAllVisibleRecordsRemote(program: _program, userId: scopedUserId, dateRange: _range);
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _ProgramChip(
                          label: 'Malaria',
                          selected: _program == HealthProgram.malaria,
                          color: ProgramColors.malaria,
                          onTap: () {
                            setState(() {
                              _program = HealthProgram.malaria;
                              if (!widget.todayOnly) {
                                final scopedUserId = hasGlobalView ? null : userId;
                                _remoteFuture = context.read<TestRecordService>().fetchAllVisibleRecordsRemote(program: _program, userId: scopedUserId, dateRange: _range);
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _ProgramChip(
                          label: 'HIV',
                          selected: _program == HealthProgram.hiv,
                          color: ProgramColors.hiv,
                          onTap: () {
                            setState(() {
                              _program = HealthProgram.hiv;
                              if (!widget.todayOnly) {
                                final scopedUserId = hasGlobalView ? null : userId;
                                _remoteFuture = context.read<TestRecordService>().fetchAllVisibleRecordsRemote(program: _program, userId: scopedUserId, dateRange: _range);
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (widget.todayOnly)
                        Text('${localRecords.length} record(s)', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))
                      else
                        const SizedBox(),
                      const Spacer(),
                      if (!widget.todayOnly)
                        TextButton.icon(
                          onPressed: () => context.push('/test-records?today=1'),
                          icon: Icon(Icons.today, color: Theme.of(context).colorScheme.primary),
                          label: const Text('Today'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.todayOnly ? () => service.initialize() : _refreshRemote,
                child: widget.todayOnly
                    ? (localRecords.isEmpty
                        ? ListView(
                            padding: AppSpacing.paddingLg,
                            children: [
                              const SizedBox(height: 40),
                              Icon(Icons.receipt_long, size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Center(
                                child: Text('No test records found.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ),
                            ],
                          )
                        : _DatedTestList(records: localRecords, fmtDay: _fmtDay))
                    : FutureBuilder<List<TestRecord>>(
                        future: _remoteFuture,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final records = (snap.data ?? const <TestRecord>[]).toList();
                          records.retainWhere((r) => r.program != HealthProgram.tb);
                          if (_program != null) {
                            // Remote query already filters by program, but keep this as a safety net.
                            records.retainWhere((r) => r.program == _program);
                          }
                          // Extra safety in case backend schema prevented date filter from applying.
                          final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
                          final endInclusive = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59, 999);
                          records.retainWhere((r) => !r.testDate.isBefore(start) && !r.testDate.isAfter(endInclusive));
                          return records.isEmpty
                              ? ListView(
                                  padding: AppSpacing.paddingLg,
                                  children: [
                                    const SizedBox(height: 40),
                                    Icon(Icons.receipt_long, size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Center(
                                      child: Text('No test records found.', style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ),
                                  ],
                                )
                              : _DatedTestList(records: records, fmtDay: _fmtDay);
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

class _DatedTestList extends StatelessWidget {
  final List<TestRecord> records;
  final String Function(DateTime) fmtDay;

  const _DatedTestList({required this.records, required this.fmtDay});

  @override
  Widget build(BuildContext context) {
    final sorted = records.toList()..sort((a, b) => b.testDate.compareTo(a.testDate));
    return ListView.builder(
      padding: AppSpacing.paddingLg,
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final r = sorted[index];
        final day = fmtDay(r.testDate);
        final prevDay = index == 0 ? null : fmtDay(sorted[index - 1].testDate);
        final showHeader = day != prevDay;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Text(day, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ],
            _TestRecordRow(record: r),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}

class _ProgramChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _ProgramChip({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = color ?? scheme.primary;

    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: base.withValues(alpha: 0.08),
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

class _TestRecordRow extends StatelessWidget {
  final TestRecord record;

  const _TestRecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final color = switch (record.syncStatus) {
      SyncStatus.synced => SyncColors.synced,
      SyncStatus.pending => SyncColors.pending,
      SyncStatus.syncing => SyncColors.syncing,
      SyncStatus.failed => SyncColors.failed,
    };

    return InkWell(
      onTap: () => context.push('/test-records/${record.id}'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25), width: 1)),
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
                  Row(
                    children: [
                      ProgramBadge(program: record.program),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${record.clientId} • ${_formatDateTime(record.testDate)}',
                          style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
