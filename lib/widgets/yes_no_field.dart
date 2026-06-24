import 'package:flutter/material.dart';

/// A modern Yes/No control that saves a boolean value, replacing old on/off toggles.
///
/// - `value == true` => Yes
/// - `value == false` => No
class YesNoField extends StatelessWidget {
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const YesNoField({super.key, required this.label, required this.value, required this.onChanged, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Yes')),
              ButtonSegment(value: false, label: Text('No')),
            ],
            selected: value == null ? const <bool>{} : {value!},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              onChanged(s.first);
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: WidgetStatePropertyAll(BorderSide(color: scheme.outline.withValues(alpha: 0.35))),
            ),
          ),
        ],
      ),
    );
  }
}
