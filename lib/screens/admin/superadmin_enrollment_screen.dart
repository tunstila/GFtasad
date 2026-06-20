import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/superadmin_analytics_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class SuperAdminEnrollmentScreen extends StatefulWidget {
  final ProviderType? initialProviderType;

  const SuperAdminEnrollmentScreen({super.key, this.initialProviderType});

  @override
  State<SuperAdminEnrollmentScreen> createState() => _SuperAdminEnrollmentScreenState();
}

class _SuperAdminEnrollmentScreenState extends State<SuperAdminEnrollmentScreen> {
  ProviderType? _providerType;
  String? _state;
  String? _lga;

  bool _loading = true;
  String? _error;
  List<EnrolledProviderRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _providerType = widget.initialProviderType;
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
      final rows = await SuperAdminAnalyticsService.fetchEnrolledProviders(providerType: _providerType, state: _state, lga: _lga);
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
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _providerType == null
        ? 'Enrolled Field Providers'
        : (_providerType == ProviderType.ppmv ? 'Enrolled PPMVs' : 'Enrolled CPs');

    final states = _distinctSorted(_rows.map((e) => (e.state ?? 'Unknown')).toList());
    final lgas = _distinctSorted(_rows.where((e) => (_state ?? '').isEmpty || (e.state ?? 'Unknown') == _state).map((e) => (e.lga ?? 'Unknown')).toList());

    final filtered = _rows.where((r) {
      if ((_state ?? '').trim().isNotEmpty && (r.state ?? 'Unknown') != _state) return false;
      if ((_lga ?? '').trim().isNotEmpty && (r.lga ?? 'Unknown') != _lga) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
                  Expanded(child: Text('Results', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Text('${filtered.length}', style: context.textStyles.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w900)),
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
                            ? Center(child: Text('No users found for the current filters.', style: context.textStyles.bodyMedium))
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) => _EnrolledProviderCard(row: filtered[i]),
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

class _EnrolledProviderCard extends StatelessWidget {
  final EnrolledProviderRow row;

  const _EnrolledProviderCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[];
    if ((row.providerType?.name ?? '').isNotEmpty) subtitleParts.add(row.providerType!.name.toUpperCase());
    if ((row.facilityName ?? '').trim().isNotEmpty) subtitleParts.add(row.facilityName!.trim());
    if ((row.lga ?? '').trim().isNotEmpty) subtitleParts.add(row.lga!.trim());
    if ((row.state ?? '').trim().isNotEmpty) subtitleParts.add(row.state!.trim());

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
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.person_pin_circle_outlined, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitleParts.join(' • '), style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3)),
                const SizedBox(height: 8),
                _MetaLine(icon: Icons.email_outlined, value: row.contactEmail ?? row.email),
                if ((row.ward ?? '').trim().isNotEmpty) _MetaLine(icon: Icons.map_outlined, value: 'Ward: ${row.ward}'),
                if ((row.businessAddress ?? '').trim().isNotEmpty) _MetaLine(icon: Icons.location_on_outlined, value: row.businessAddress!),
                const SizedBox(height: 6),
                Text('Enrolled: ${_formatDate(row.createdAt)}', style: context.textStyles.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
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

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String value;

  const _MetaLine({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 2)),
        ],
      ),
    );
  }
}
