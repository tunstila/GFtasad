import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:mediflow/utils/csv_downloader.dart';
import 'package:mediflow/widgets/date_range_filter_bar.dart';
import 'package:mediflow/widgets/offline_banner.dart';
import 'package:provider/provider.dart';

class LoginTrackerScreen extends StatefulWidget {
  const LoginTrackerScreen({super.key});

  @override
  State<LoginTrackerScreen> createState() => _LoginTrackerScreenState();
}

class _LoginTrackerScreenState extends State<LoginTrackerScreen> {
  late DateTimeRange _range;
  String _roleFilter = '';
  String _query = '';
  bool _loading = false;
  bool _exporting = false;
  List<Map<String, dynamic>> _sessions = const [];
  final Map<String, Map<String, dynamic>> _activityBySessionId = {};
  String? _error;

  int? _totalSignIns;
  int? _uniqueAccounts;

  @override
  void initState() {
    super.initState();
    // Default: today.
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: start, end: end);
    _refresh();
  }

  bool get _isTodayRange {
    final now = DateTime.now();
    final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final end = DateTime(_range.end.year, _range.end.month, _range.end.day);
    final today = DateTime(now.year, now.month, now.day);
    return start == today && end == today;
  }

  Future<void> _applyQuickRange(String key) async {
    final now = DateTime.now();
    DateTimeRange next;
    if (key == 'today') {
      final d = DateTime(now.year, now.month, now.day);
      next = DateTimeRange(start: d, end: d);
    } else if (key == 'yesterday') {
      final d = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      next = DateTimeRange(start: d, end: d);
    } else {
      // last7
      final end = DateTime(now.year, now.month, now.day);
      final start = end.subtract(const Duration(days: 6));
      next = DateTimeRange(start: start, end: end);
    }
    setState(() => _range = next);
    await _refresh();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    await _refresh();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthService>();
    if (!auth.isSuperAdminFull) {
      setState(() {
        _sessions = const [];
        _error = 'Forbidden';
        _totalSignIns = null;
        _uniqueAccounts = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? start;
      String? end;
      final startLocal = DateTime(_range.start.year, _range.start.month, _range.start.day);
      final endLocal = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59, 999);
      start = startLocal.toUtc().toIso8601String();
      end = endLocal.toUtc().toIso8601String();

      final results = await Future.wait([
        SupabaseConfig.client.functions.invoke(
          'login_tracker',
          body: {
            'action': 'list_sessions',
            'start': start,
            'end': end,
            if (_roleFilter.isNotEmpty) 'role': _roleFilter,
            // On-screen list is intentionally capped for speed.
            'limit': 100,
            'includeActivity': false,
          },
        ),
        SupabaseConfig.client.functions.invoke(
          'login_tracker',
          body: {
            'action': 'summary',
            'start': start,
            'end': end,
          },
        ),
      ]);

      final listRes = results[0];
      final summaryRes = results[1];

      final listData = listRes.data;
      final rows = listData is Map ? listData['sessions'] : null;
      final parsed = <Map<String, dynamic>>[];
      if (rows is List) {
        for (final item in rows) {
          if (item is Map) parsed.add(Map<String, dynamic>.from(item));
        }
      }

      final sumData = summaryRes.data;
      final total = (sumData is Map) ? sumData['totalSignIns'] : null;
      final unique = (sumData is Map) ? sumData['uniqueAccounts'] : null;

      setState(() {
        _sessions = parsed;
        _totalSignIns = (total is num) ? total.toInt() : int.tryParse(total?.toString() ?? '');
        _uniqueAccounts = (unique is num) ? unique.toInt() : int.tryParse(unique?.toString() ?? '');
      });
    } catch (e) {
      debugPrint('Login tracker fetch failed: $e');
      setState(() => _error = 'Failed to load login tracker.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadCsv() async {
    final auth = context.read<AuthService>();
    if (!auth.isSuperAdminFull || _exporting) return;

    setState(() => _exporting = true);
    try {
      final startLocal = DateTime(_range.start.year, _range.start.month, _range.start.day);
      final endLocal = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59, 999);
      final start = startLocal.toUtc().toIso8601String();
      final end = endLocal.toUtc().toIso8601String();

      final res = await SupabaseConfig.client.functions.invoke(
        'login_tracker',
        body: {
          'action': 'export_csv',
          'start': start,
          'end': end,
          if (_roleFilter.isNotEmpty) 'role': _roleFilter,
        },
      );

      final data = res.data;
      if (data is! Map) throw Exception('Unexpected export response');
      final filename = (data['filename'] ?? 'login_tracker.csv').toString();
      final csv = (data['csv'] ?? '').toString();
      if (csv.trim().isEmpty) throw Exception('Export returned an empty CSV');

      final savedPath = await downloadCsv(filename: filename, csvUtf8: csv);
      if (!mounted) return;
      final rowCount = data['rowCount'];
      final msg = savedPath == null ? 'Downloaded ${rowCount ?? ''} rows.' : 'Saved ${rowCount ?? ''} rows to: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint('Login tracker CSV export failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _loadActivityFor(String sessionId) async {
    if (_activityBySessionId.containsKey(sessionId)) return;
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'login_tracker',
        body: {'action': 'get_session_activity', 'sessionId': sessionId},
      );
      final data = res.data;
      final activity = (data is Map && data['activity'] is Map) ? Map<String, dynamic>.from(data['activity']) : null;
      if (activity == null || !mounted) return;
      setState(() => _activityBySessionId[sessionId] = activity);
    } catch (e) {
      debugPrint('Load session activity failed: $e');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sessions;
    return _sessions.where((s) {
      final id = (s['userId'] ?? '').toString().toLowerCase();
      final name = (s['name'] ?? '').toString().toLowerCase();
      final role = (s['role'] ?? '').toString().toLowerCase();
      return id.contains(q) || name.contains(q) || role.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Tracker'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                    Row(
                      children: [
                        Expanded(child: DateRangeFilterBar(range: _range, onPick: _pickRange)),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: _exporting ? null : _downloadCsv,
                          icon: _exporting
                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                              : Icon(Icons.download, color: scheme.primary),
                          label: Text('Download Login Tracker CSV', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Today'),
                          selected: _isTodayRange,
                          onSelected: (_) => _applyQuickRange('today'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Yesterday'),
                          selected: !_isTodayRange && _range.duration.inDays == 0 && DateTime.now().difference(_range.start).inDays == 1,
                          onSelected: (_) => _applyQuickRange('yesterday'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Last 7 days'),
                          selected: _range.duration.inDays >= 6,
                          onSelected: (_) => _applyQuickRange('last7'),
                        ),
                        const Spacer(),
                        if (_totalSignIns != null && _uniqueAccounts != null)
                          Text(
                            'Total: $_totalSignIns • Unique: $_uniqueAccounts',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isTodayRange ? 'Showing most recent 100 sign-ins today' : 'Showing most recent 100 sign-ins (filtered)',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search (name, role, user id)',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<String>(
                        tooltip: 'Filter role',
                        onSelected: (v) async {
                          setState(() => _roleFilter = v == 'all' ? '' : v);
                          await _refresh();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'all', child: Text('All roles')),
                          PopupMenuItem(value: 'fieldProvider', child: Text('fieldProvider')),
                          PopupMenuItem(value: 'admin', child: Text('admin')),
                          PopupMenuItem(value: 'superAdmin', child: Text('superAdmin')),
                          PopupMenuItem(value: 'supplier', child: Text('supplier')),
                          PopupMenuItem(value: 'nationalMalaria', child: Text('nationalMalaria')),
                          PopupMenuItem(value: 'nationalHIVTB', child: Text('nationalHIVTB')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.filter_alt_outlined, color: scheme.primary),
                              const SizedBox(width: 6),
                              Text(_roleFilter.isEmpty ? 'Role' : _roleFilter, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!auth.isSuperAdminFull)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Only superAdmin can view this page.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error)))
                  : _buildList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _filtered;

    if (_loading && _sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No sessions found for this range.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = rows[i];
        final name = (s['name'] ?? 'Unknown').toString();
        final role = (s['role'] ?? '').toString();
        final providerType = (s['providerType'] ?? '').toString();
        final status = (s['status'] ?? '').toString();
        final signedInAt = (s['signedInAt'] ?? '').toString();
        final lastSeenAt = (s['lastSeenAt'] ?? '').toString();
        final signedOutAt = (s['signedOutAt'] ?? '').toString();
        final durationSeconds = s['durationSeconds'];
        final sessionId = (s['sessionId'] ?? '').toString();
        final cachedActivity = _activityBySessionId[sessionId];

        final state = (s['state'] ?? '').toString();
        final lga = (s['lga'] ?? '').toString();
        final ward = (s['ward'] ?? '').toString();

        Color statusColor;
        switch (status) {
          case 'active':
            statusColor = scheme.primary;
            break;
          case 'signed_out':
            statusColor = scheme.tertiary;
            break;
          default:
            statusColor = scheme.onSurfaceVariant;
        }

        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            collapsedIconColor: scheme.onSurfaceVariant,
            iconColor: scheme.onSurfaceVariant,
            title: Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _pill(context, role.isEmpty ? '—' : role, scheme.secondaryContainer, scheme.onSecondaryContainer),
                  if (providerType.isNotEmpty) _pill(context, providerType, scheme.tertiaryContainer, scheme.onTertiaryContainer),
                  _pill(context, status, statusColor.withValues(alpha: 0.12), statusColor),
                  if (state.isNotEmpty) _pill(context, state, scheme.surfaceContainerHighest, scheme.onSurface),
                  if (lga.isNotEmpty) _pill(context, lga, scheme.surfaceContainerHighest, scheme.onSurface),
                  if (ward.isNotEmpty) _pill(context, ward, scheme.surfaceContainerHighest, scheme.onSurface),
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv(context, 'User ID', (s['userId'] ?? '').toString()),
                    _kv(context, 'Email', (s['email'] ?? '').toString().isEmpty ? '—' : (s['email'] ?? '').toString()),
                    _kv(context, 'Signed in', signedInAt),
                    _kv(context, 'Last seen', lastSeenAt),
                    _kv(context, 'Signed out', signedOutAt.isEmpty ? '—' : signedOutAt),
                    _kv(context, 'Duration', durationSeconds == null ? '— (last-seen based if not signed out)' : '${durationSeconds}s'),
                    const SizedBox(height: 10),
                    Text('Records created (within session window):', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    if (cachedActivity == null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: sessionId.isEmpty ? null : () => _loadActivityFor(sessionId),
                          icon: Icon(Icons.auto_awesome, color: scheme.primary),
                          label: Text('Load activity', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _pill(context, 'Malaria: ${cachedActivity['malariaCount'] ?? 0}', scheme.surfaceContainerHighest, scheme.onSurface),
                          _pill(context, 'HIV: ${cachedActivity['hivCount'] ?? 0}', scheme.surfaceContainerHighest, scheme.onSurface),
                          _pill(context, 'PM: ${cachedActivity['preventionMessagingCount'] ?? 0}', scheme.surfaceContainerHighest, scheme.onSurface),
                          _pill(context, 'Total: ${cachedActivity['totalCount'] ?? 0}', scheme.surfaceContainerHighest, scheme.onSurface),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(BuildContext context, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w800)),
      );

  Widget _kv(BuildContext context, String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 98, child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
          const SizedBox(width: 10),
          Expanded(child: Text(v, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35))),
        ],
      ),
    );
  }
}
