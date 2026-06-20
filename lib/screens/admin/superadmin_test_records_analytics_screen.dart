import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/superadmin_analytics_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class SuperAdminTestRecordsAnalyticsScreen extends StatefulWidget {
  const SuperAdminTestRecordsAnalyticsScreen({super.key});

  @override
  State<SuperAdminTestRecordsAnalyticsScreen> createState() => _SuperAdminTestRecordsAnalyticsScreenState();
}

class _SuperAdminTestRecordsAnalyticsScreenState extends State<SuperAdminTestRecordsAnalyticsScreen> {
  String? _state;
  String? _lga;
  String? _program;

  bool _loading = true;
  String? _error;
  List<TestRecordAnalyticsRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isSuperAdminFull) {
      context.go('/admin/dashboard');
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await SuperAdminAnalyticsService.fetchTestRecords(state: _state, lga: _lga, program: _program);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _state = null;
      _lga = null;
      _program = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final states = _distinctSorted(_rows.map((e) => (e.providerState ?? 'Unknown')).toList());
    final lgas = _distinctSorted(_rows.where((e) => (_state ?? '').isEmpty || (e.providerState ?? 'Unknown') == _state).map((e) => (e.providerLga ?? 'Unknown')).toList());
    final programs = _distinctSorted(_rows.map((e) => e.program).toList());

    final filtered = _rows.where((r) {
      if ((_state ?? '').trim().isNotEmpty && (r.providerState ?? 'Unknown') != _state) return false;
      if ((_lga ?? '').trim().isNotEmpty && (r.providerLga ?? 'Unknown') != _lga) return false;
      if ((_program ?? '').trim().isNotEmpty && r.program != _program) return false;
      return true;
    }).toList();

    final total = filtered.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cumulative Test Records'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                : const Icon(Icons.refresh),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: states.contains(_state) ? _state : null,
                      decoration: InputDecoration(
                        labelText: 'State',
                        filled: true,
                        fillColor: scheme.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                      ),
                      items: states.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        setState(() {
                          _state = v;
                          _lga = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: lgas.contains(_lga) ? _lga : null,
                      decoration: InputDecoration(
                        labelText: 'LGA',
                        filled: true,
                        fillColor: scheme.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                      ),
                      items: lgas.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _lga = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: programs.contains(_program) ? _program : null,
                decoration: InputDecoration(
                  labelText: 'Intervention area',
                  filled: true,
                  fillColor: scheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                ),
                items: programs.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _program = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _clearFilters,
                      icon: Icon(Icons.filter_alt_off, color: scheme.primary),
                      label: Text('Clear', style: TextStyle(color: scheme.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.search, color: Colors.white),
                      label: const Text('Apply', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Client test rows', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.tertiary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
                    ),
                    child: Text('$total', style: context.textStyles.labelLarge?.copyWith(color: scheme.tertiary, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_error != null)
                        ? Center(child: Text('Failed to load.\n$_error', textAlign: TextAlign.center))
                        : (filtered.isEmpty)
                            ? Center(child: Text('No test records found for the current filters.', style: context.textStyles.bodyMedium))
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) => _TestRecordRowCard(row: filtered[i]),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _distinctSorted(List<String> raw) {
    final set = <String>{};
    for (final v in raw) {
      final t = v.trim();
      if (t.isEmpty) continue;
      set.add(t);
    }
    final list = set.toList();
    list.sort();
    return list;
  }
}

class _TestRecordRowCard extends StatelessWidget {
  final TestRecordAnalyticsRow row;

  const _TestRecordRowCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = (row.providerState ?? 'Unknown').trim();
    final lga = (row.providerLga ?? 'Unknown').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: scheme.tertiary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.fact_check_outlined, color: scheme.tertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.clientName.isEmpty ? 'Unknown client' : row.clientName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Client ID: ${row.clientId}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(text: row.program, color: scheme.primary),
                    _Chip(text: '$state • $lga', color: scheme.onSurfaceVariant),
                    _Chip(text: _formatDate(row.testDate), color: scheme.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;

  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: context.textStyles.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w900)),
    );
  }
}
