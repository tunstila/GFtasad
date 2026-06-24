import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mediflow/models/prevention_messaging_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/prevention_messaging_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class PreventionMessagingRecordsHistoryScreen extends StatefulWidget {
  final bool todayOnly;

  const PreventionMessagingRecordsHistoryScreen({super.key, this.todayOnly = false});

  @override
  State<PreventionMessagingRecordsHistoryScreen> createState() => _PreventionMessagingRecordsHistoryScreenState();
}

class _PreventionMessagingRecordsHistoryScreenState extends State<PreventionMessagingRecordsHistoryScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure local cache is hydrated; this is safe to call repeatedly.
    context.read<PreventionMessagingRecordService>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final svc = context.watch<PreventionMessagingRecordService>();

    final userId = auth.currentUser?.id ?? '';

    List<PreventionMessagingRecord> records;
    if (widget.todayOnly) {
      records = userId.isEmpty ? const [] : svc.getTodayRecords(userId);
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      // We only show "my" records here to match the fieldProvider drill-down expectation.
      records = userId.isEmpty ? const [] : svc.records.where((r) => r.userId == userId).toList();
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.todayOnly ? 'Today\'s Prevention Messaging' : 'Prevention Messaging'),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => svc.syncNow(),
          child: records.isEmpty
              ? ListView(
                  padding: AppSpacing.paddingLg,
                  children: [
                    const SizedBox(height: 40),
                    Icon(Icons.campaign, size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'No prevention messaging records found.',
                        style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: AppSpacing.paddingLg,
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _PreventionMessagingRow(record: records[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/record-prevention-messaging');
          if (!context.mounted) return;
          // Pull any newly-synced records and refresh.
          await svc.syncNow();
        },
        backgroundColor: ProgramColors.prevention,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Record'),
      ),
    );
  }
}

class _PreventionMessagingRow extends StatelessWidget {
  final PreventionMessagingRecord record;

  const _PreventionMessagingRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ProgramColors.prevention;
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => _PreventionMessagingDetailsSheet(record: record),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.campaign, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.clientName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    '${record.clientId} • ${record.sex} • ${record.age}y',
                    style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PreventionMessagingDetailsSheet extends StatelessWidget {
  final PreventionMessagingRecord record;

  const _PreventionMessagingDetailsSheet({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: Text(label, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
              Expanded(child: Text(value, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
        );

    String yn(bool v) => v ? 'Yes' : 'No';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Prevention Messaging Details', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              row('Client', record.clientName),
              row('Client ID', record.clientId),
              row('Sex', record.sex),
              row('Age', record.age.toString()),
              row('Phone', record.phoneNumber),
              row('Client groups', record.clientGroups.isEmpty ? '-' : record.clientGroups.join(', ')),
              row('First time visit', yn(record.firstTimeVisit)),
              row('Referred from', record.otherReferredFrom?.trim().isNotEmpty == true ? '${record.referredFrom} (${record.otherReferredFrom})' : record.referredFrom),
              row('Educated on HIV prevention', yn(record.educatedOnHivPrevention)),
              row('Educated on HIV testing options', yn(record.educatedOnHivTestingOptions)),
              row('Educated on malaria prevention', yn(record.educatedOnMalariaPrevention)),
              row('Referral services', record.referralServices.isEmpty ? '-' : record.referralServices.join(', ')),
              if ((record.otherReferralService ?? '').trim().isNotEmpty) row('Other service', record.otherReferralService!.trim()),
              if ((record.referralFacility ?? '').trim().isNotEmpty) row('Referral facility', record.referralFacility!.trim()),
              const SizedBox(height: 12),
              Text(
                'Sync: ${record.syncStatus.name}',
                style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
