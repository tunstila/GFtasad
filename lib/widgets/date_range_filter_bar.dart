import 'package:flutter/material.dart';
import 'package:mediflow/theme.dart';

class DateRangeFilterBar extends StatelessWidget {
  final DateTimeRange range;
  final VoidCallback onPick;

  const DateRangeFilterBar({super.key, required this.range, required this.onPick});

  String _fmt(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.date_range, color: scheme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Date range', style: context.textStyles.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${_fmt(range.start)} → ${_fmt(range.end)}', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ]),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}
