import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/prevention_messaging_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/prevention_messaging_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class PreventionMessagingHistoryScreen extends StatelessWidget {
  final bool todayOnly;

  const PreventionMessagingHistoryScreen({super.key, required this.todayOnly});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final myUserId = auth.currentUser?.id ?? '';
    final service = context.watch<PreventionMessagingService>();

    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = d0.add(const Duration(days: 1));

    final List<PreventionMessagingRecord> rows = service.records.where((r) {
      if (myUserId.isNotEmpty && r.userId != myUserId && !(auth.currentUser?.hasGlobalView ?? false)) return false;
      if (!todayOnly) return true;
      return r.createdAt.isAfter(d0) && r.createdAt.isBefore(d1);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(todayOnly ? 'Messaging Today' : 'Prevention Messaging'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => context.read<PreventionMessagingService>().initialize(),
          child: ListView.separated(
            padding: AppSpacing.paddingLg,
            itemCount: rows.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  '${rows.length} record${rows.length == 1 ? '' : 's'}',
                  style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                );
              }
              final r = rows[i - 1];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.campaign, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.clientName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(
                            '${r.clientId} • Age ${r.age} • ${r.sex}',
                            style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Groups: ${r.clientGroups.join(', ')}',
                            style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${r.createdAt.hour.toString().padLeft(2, '0')}:${r.createdAt.minute.toString().padLeft(2, '0')}',
                      style: context.textStyles.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
