import 'package:flutter/material.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/theme.dart';

class ProgramBadge extends StatelessWidget {
  final HealthProgram program;
  final bool showLabel;

  const ProgramBadge({
    super.key,
    required this.program,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final label = _getLabel();

    if (!showLabel) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        label,
        style: context.textStyles.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (program) {
      case HealthProgram.malaria:
        return ProgramColors.malaria;
      case HealthProgram.hiv:
        return ProgramColors.hiv;
      case HealthProgram.tb:
        return ProgramColors.tb;
    }
  }

  String _getLabel() {
    switch (program) {
      case HealthProgram.malaria:
        return 'MALARIA';
      case HealthProgram.hiv:
        return 'HIV';
      case HealthProgram.tb:
        return 'TB';
    }
  }
}
