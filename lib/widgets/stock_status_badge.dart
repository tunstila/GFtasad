import 'package:flutter/material.dart';
import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/theme.dart';

class StockStatusBadge extends StatelessWidget {
  final StockStatus status;

  const StockStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      StockStatus.ok => ('OK', AlertColors.success),
      StockStatus.low => ('Low', AlertColors.warning),
      StockStatus.stockOut => ('Stock-Out', AlertColors.critical),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: color.withValues(alpha: 0.35), width: 1)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: context.textStyles.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
