import 'package:flutter/material.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/theme.dart';

class SyncBadge extends StatelessWidget {
  final SyncStatus status;
  final bool showLabel;

  const SyncBadge({
    super.key,
    required this.status,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final label = _getLabel();
    final icon = _getIcon();

    if (!showLabel) {
      return Icon(icon, size: 16, color: color);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textStyles.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (status) {
      case SyncStatus.synced:
        return SyncColors.synced;
      case SyncStatus.pending:
        return SyncColors.pending;
      case SyncStatus.syncing:
        return SyncColors.syncing;
      case SyncStatus.failed:
        return SyncColors.failed;
    }
  }

  String _getLabel() {
    switch (status) {
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.pending:
        return 'Pending';
      case SyncStatus.syncing:
        return 'Syncing';
      case SyncStatus.failed:
        return 'Failed';
    }
  }

  IconData _getIcon() {
    switch (status) {
      case SyncStatus.synced:
        return Icons.check_circle;
      case SyncStatus.pending:
        return Icons.schedule;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.failed:
        return Icons.error;
    }
  }
}
