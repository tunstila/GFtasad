import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/services/fieldprovider_analytics_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class FieldProviderAnalyticsScreen extends StatefulWidget {
  final String? initialState;
  final String? initialProviderType;

  const FieldProviderAnalyticsScreen({super.key, this.initialState, this.initialProviderType});

  @override
  State<FieldProviderAnalyticsScreen> createState() => _FieldProviderAnalyticsScreenState();
}

class _FieldProviderAnalyticsScreenState extends State<FieldProviderAnalyticsScreen> {
  String? _selectedState;
  String? _selectedProviderType;

  @override
  void initState() {
    super.initState();
    _selectedState = widget.initialState;
    _selectedProviderType = widget.initialProviderType;
  }

  Future<FieldProviderAnalyticsSnapshot> _load(FieldProviderAnalyticsService svc) => svc.fetchSnapshot(
    selectedState: _selectedState,
    selectedProviderType: _selectedProviderType,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final svc = context.watch<FieldProviderAnalyticsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Providers'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              svc.invalidate();
              setState(() {});
            },
            icon: const Icon(Icons.refresh),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<FieldProviderAnalyticsSnapshot>(
          future: _load(svc),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: AppSpacing.paddingLg,
                  child: Text('Failed to load analytics. ${snap.error}', textAlign: TextAlign.center),
                ),
              );
            }

            final data = snap.data!;
            final stateOptions = _buildStateOptions(data.byState);
            final typeOptions = _buildTypeOptions(data.byType);

            return RefreshIndicator(
              onRefresh: () async {
                svc.invalidate();
                setState(() {});
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.paddingLg,
                children: [
                  _SummaryHeader(total: data.total, selectedState: _selectedState, selectedType: _selectedProviderType),
                  const SizedBox(height: 12),
                  _FiltersCard(
                    selectedState: _selectedState,
                    selectedProviderType: _selectedProviderType,
                    stateOptions: stateOptions,
                    providerTypeOptions: typeOptions,
                    onChangedState: (v) => setState(() => _selectedState = v),
                    onChangedType: (v) => setState(() => _selectedProviderType = v),
                    onClear: () => setState(() {
                      _selectedState = null;
                      _selectedProviderType = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  Text('Breakdown by State', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  _BreakdownList(entries: data.byState, emptyText: 'No field providers found for this filter.'),
                  const SizedBox(height: 18),
                  Text('Breakdown by Provider Type', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  _BreakdownList(entries: data.byType, emptyText: 'No provider types found for this filter.'),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Text('Matching Accounts', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                      Text('${data.rows.length}', style: context.textStyles.titleMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (data.rows.isEmpty)
                    _EmptyListCard(text: 'No accounts match the selected filters.')
                  else
                    ...data.rows.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FieldProviderRowCard(row: r),
                    )),
                  const SizedBox(height: 18),
                  Text(
                    'Counts are computed server-side using scoped RPCs to prevent analytics drift.',
                    style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<String> _buildStateOptions(List<FieldProviderBreakdownEntry> entries) {
    final labels = entries.map((e) => e.label).toSet().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (!labels.contains('Unknown')) labels.add('Unknown');
    return labels;
  }

  List<String> _buildTypeOptions(List<FieldProviderBreakdownEntry> entries) {
    final base = <String>{'PPMV', 'CP', 'CHP', 'Unknown'};
    base.addAll(entries.map((e) => e.label));
    final labels = base.toList();
    labels.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return labels;
  }
}

class _SummaryHeader extends StatelessWidget {
  final int total;
  final String? selectedState;
  final String? selectedType;

  const _SummaryHeader({required this.total, required this.selectedState, required this.selectedType});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final chips = <Widget>[];
    if (selectedState != null) chips.add(_FilterChip(label: selectedState!));
    if (selectedType != null) chips.add(_FilterChip(label: selectedType!));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Field Providers', style: context.textStyles.labelLarge?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('$total', style: context.textStyles.displaySmall?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (chips.isEmpty)
            Text('All visible accounts', style: context.textStyles.bodySmall?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.85), height: 1.4))
          else
            Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;

  const _FilterChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.onPrimaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.onPrimaryContainer.withValues(alpha: 0.18)),
      ),
      child: Text(label, style: context.textStyles.labelMedium?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
    );
  }
}

class _FiltersCard extends StatelessWidget {
  final String? selectedState;
  final String? selectedProviderType;
  final List<String> stateOptions;
  final List<String> providerTypeOptions;
  final ValueChanged<String?> onChangedState;
  final ValueChanged<String?> onChangedType;
  final VoidCallback onClear;

  const _FiltersCard({
    required this.selectedState,
    required this.selectedProviderType,
    required this.stateOptions,
    required this.providerTypeOptions,
    required this.onChangedState,
    required this.onChangedType,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text('Filters', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              TextButton(
                onPressed: (selectedState == null && selectedProviderType == null) ? null : onClear,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DropdownLine(
            label: 'State',
            value: selectedState,
            options: stateOptions,
            onChanged: onChangedState,
          ),
          const SizedBox(height: 10),
          _DropdownLine(
            label: 'Provider type',
            value: selectedProviderType,
            options: providerTypeOptions,
            onChanged: onChangedType,
          ),
          const SizedBox(height: 8),
          Text(
            'Selecting one filter refines the other breakdown automatically.',
            style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _DropdownLine extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _DropdownLine({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(label, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All')),
            ...options.map((o) => DropdownMenuItem<String>(value: o, child: Text(o, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _BreakdownList extends StatelessWidget {
  final List<FieldProviderBreakdownEntry> entries;
  final String emptyText;

  const _BreakdownList({required this.entries, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) {
      return _EmptyListCard(text: emptyText);
    }

    return Column(
      children: entries
          .take(24)
          .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.label, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${e.totalCount}', style: context.textStyles.labelMedium?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _EmptyListCard extends StatelessWidget {
  final String text;

  const _EmptyListCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4))),
        ],
      ),
    );
  }
}

class _FieldProviderRowCard extends StatelessWidget {
  final FieldProviderAnalyticsRow row;

  const _FieldProviderRowCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final subtitleBits = <String>[row.state, row.providerType];
    final subtitle = subtitleBits.where((e) => e.trim().isNotEmpty).join(' • ');

    return InkWell(
      onTap: () {
        // No dedicated user details page in the current app; keep this future-proof.
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
                  Text(row.username, style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(row.contactEmail ?? row.email, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  _KeyValue(label: 'State', value: row.state),
                  const SizedBox(height: 8),
                  _KeyValue(label: 'Provider type', value: row.providerType),
                  const SizedBox(height: 8),
                  _KeyValue(label: 'Created', value: _fmt(row.createdAt)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.pop(),
                          icon: Icon(Icons.close, color: scheme.primary),
                          label: Text('Close', style: TextStyle(color: scheme.primary)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.person_outline, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.username, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        Expanded(child: Text(value, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
      ],
    );
  }
}
