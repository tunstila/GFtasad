import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/program_badge.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class TestRecordDetailScreen extends StatelessWidget {
  final String recordId;

  const TestRecordDetailScreen({super.key, required this.recordId});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final service = context.watch<TestRecordService>();

    final user = auth.currentUser;
    final role = user?.role;
    final hasGlobalView = user?.hasGlobalView ?? false;

    final record = service.records.where((r) => r.id == recordId).cast<TestRecord?>().firstOrNull;
    if (record == null) {
      return Scaffold(appBar: AppBar(title: const Text('Test Record'), actions: const [AppAccountMenu()]), body: const Center(child: Text('Record not found.')));
    }

    if (!hasGlobalView && record.userId != (user?.id ?? '')) {
      return Scaffold(appBar: AppBar(title: const Text('Test Record'), actions: const [AppAccountMenu()]), body: const Center(child: Text('You do not have access to this record.')));
    }

    final syncColor = switch (record.syncStatus) {
      SyncStatus.synced => SyncColors.synced,
      SyncStatus.pending => SyncColors.pending,
      SyncStatus.syncing => SyncColors.syncing,
      SyncStatus.failed => SyncColors.failed,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Record'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.paddingLg,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(record.clientName, style: context.textStyles.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: syncColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(color: syncColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(record.syncStatus.name, style: context.textStyles.labelSmall?.copyWith(color: syncColor, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ProgramBadge(program: record.program),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Client ID: ${record.clientId}',
                          style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _KV(label: 'Test date', value: _formatDateTime(record.testDate)),
                  _KV(label: 'Sex', value: record.sex),
                  _KV(label: 'Age', value: record.age?.toString() ?? record.ageBand ?? '—'),
                  if ((record.phoneNumber ?? '').trim().isNotEmpty) _KV(label: 'Phone', value: record.phoneNumber!.trim()),
                  if (record.dateOfBirth != null) _KV(label: 'Date of birth', value: '${record.dateOfBirth!.year}-${record.dateOfBirth!.month.toString().padLeft(2, '0')}-${record.dateOfBirth!.day.toString().padLeft(2, '0')}'),
                  _KV(label: 'Visit type', value: record.visitType.name),
                  if (record.pregnant != null) _KV(label: 'Pregnant', value: record.pregnant == true ? 'Yes' : 'No'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ProgramDetailsCard(record: record),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audit', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  _KV(label: 'Created', value: _formatDateTime(record.createdAt)),
                  _KV(label: 'Updated', value: _formatDateTime(record.updatedAt)),
                  if (role == UserRole.superAdmin || role == UserRole.sfhTeam) _KV(label: 'Recorded by userId', value: record.userId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }
}

class _ProgramDetailsCard extends StatelessWidget {
  final TestRecord record;

  const _ProgramDetailsCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    List<Widget> rows = [];
    switch (record.program) {
      case HealthProgram.malaria:
        rows = [
          if ((record.clientAddress ?? '').trim().isNotEmpty) _KV(label: 'Client address', value: record.clientAddress!.trim()),
          if ((record.clientGroups ?? const []).isNotEmpty) _KV(label: 'Client group', value: record.clientGroups!.join(', ')),
          if (record.firstTimeVisit != null) _KV(label: 'First time visit', value: record.firstTimeVisit == true ? 'Yes' : 'No'),
          if ((record.referredFrom ?? '').trim().isNotEmpty) _KV(label: 'Referred from', value: record.referredFrom!.trim()),
          if ((record.otherReferralSource ?? '').trim().isNotEmpty) _KV(label: 'Other referral source', value: record.otherReferralSource!.trim()),
          if ((record.symptomsPresented ?? const []).isNotEmpty) _KV(label: 'Symptoms presented', value: record.symptomsPresented!.join(', ')),
          if ((record.otherSymptomsPresented ?? '').trim().isNotEmpty) _KV(label: 'Other symptom(s)', value: record.otherSymptomsPresented!.trim()),
          if ((record.mRDTResult ?? '').trim().isNotEmpty) _KV(label: 'mRDT result', value: record.mRDTResult!.trim()) else ...[
            _BoolKV(label: 'mRDT tested', value: record.mRDTTested),
            _BoolKV(label: 'mRDT positive', value: record.mRDTPositive),
          ],
          if ((record.actGivenOption ?? '').trim().isNotEmpty) ...[
            _KV(label: 'ACT given', value: record.actGivenOption!.trim()),
            if ((record.otherActGiven ?? '').trim().isNotEmpty) _KV(label: 'Other ACT', value: record.otherActGiven!.trim()),
          ] else
            _BoolKV(label: 'ACT given', value: record.actGiven),
          if (record.referralForDangerSigns != null) _KV(label: 'Referral for danger signs', value: record.referralForDangerSigns == true ? 'Yes' : 'No'),
          if ((record.dangerSignsReferralFacility ?? '').trim().isNotEmpty) _KV(label: 'Referral facility', value: record.dangerSignsReferralFacility!.trim()),
          if ((record.dangerSignsReferralFacility ?? '').trim().isEmpty && (record.referralFacility ?? '').trim().isNotEmpty) _KV(label: 'Referral facility', value: record.referralFacility!.trim()),
        ];
        break;
      case HealthProgram.hiv:
        rows = [
          if ((record.clientAddress ?? '').trim().isNotEmpty) _KV(label: 'Client address', value: record.clientAddress!.trim()),
          if ((record.clientGroups ?? const []).isNotEmpty) _KV(label: 'Client group', value: record.clientGroups!.join(', ')),
          if (record.firstTimeVisit != null) _KV(label: 'First time visit', value: record.firstTimeVisit == true ? 'Yes' : 'No'),
          if ((record.referredFrom ?? '').trim().isNotEmpty) _KV(label: 'Referred from', value: record.referredFrom!.trim()),
          if ((record.otherReferralSource ?? '').trim().isNotEmpty) _KV(label: 'Other referral source', value: record.otherReferralSource!.trim()),
          _KV(label: 'Previous HIV testing', value: _hivPreviousTestingLabel(record.hivPreviousTesting) ?? '—'),
          _BoolKV(label: 'HIV counselling provided', value: record.hivCounselling),
          _KV(label: 'HTS Type', value: record.htsType?.name ?? '—'),
          if (record.htsType == HTSType.hivst) ...[
            _KV(label: 'HIVST type', value: record.hivstKitType?.name ?? '—'),
            _KV(label: 'HIVST model', value: record.hivstServiceDeliveryModel?.name ?? '—'),
          ],
          _KV(label: 'HIV test result', value: _hivTestResultLabel(record.hivTestResult) ?? '—'),
          if ((record.tbSymptomsPresented ?? const []).isNotEmpty) _KV(label: 'TB symptoms', value: record.tbSymptomsPresented!.join(', ')),
          if ((record.referralServices ?? const []).isNotEmpty) _KV(label: 'Referred for', value: record.referralServices!.join(', ')),
          if ((record.otherReferralService ?? '').trim().isNotEmpty) _KV(label: 'Other referral', value: record.otherReferralService!.trim()),
          if (record.referralFacility != null && record.referralFacility!.trim().isNotEmpty) _KV(label: 'Referral facility', value: record.referralFacility!),
          const SizedBox(height: 10),
          Text('PrEP', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.onSurface)),
          const SizedBox(height: 10),
          _BoolKV(label: 'Assessed', value: record.prepAssessed),
          _BoolKV(label: 'Eligible', value: record.prepEligible),
          _BoolKV(label: 'Offered', value: record.prepOffered),
          _BoolKV(label: 'Accepted', value: record.prepAccepted),
          _BoolKV(label: 'Newly started', value: record.prepStarted),
          _BoolKV(label: 'Continued', value: record.prepContinued),
          if (record.prepRefSource != null && record.prepRefSource!.trim().isNotEmpty) _KV(label: 'Ref source', value: record.prepRefSource!),
        ];
        break;
      case HealthProgram.tb:
        rows = [
          Text('Legacy program (TB)', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.onSurface)),
          const SizedBox(height: 10),
          Text('TB recording has been deprecated in this app. This record is read-only historical data.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
        ];
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Program details', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }
}

String? _hivTestResultLabel(HIVTestResult? v) => switch (v) {
  HIVTestResult.reactive => 'Reactive',
  HIVTestResult.nonReactive => 'Non-reactive',
  HIVTestResult.invalid => 'Invalid',
  null => null,
};

String? _hivPreviousTestingLabel(HIVPreviousTesting? v) => switch (v) {
  HIVPreviousTesting.notPreviouslyTested => 'Not previously tested',
  HIVPreviousTesting.previouslyTestedNegative => 'Previously tested negative',
  HIVPreviousTesting.previouslyTestedPositive => 'Previously tested positive on HIV care',
  HIVPreviousTesting.previouslyTestedPositiveNotOnCare => 'Previously tested positive not on HIV care',
  null => null,
};

class _KV extends StatelessWidget {
  final String label;
  final String value;

  const _KV({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Flexible(child: Text(value, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
          ],
        ),
      );
}

class _BoolKV extends StatelessWidget {
  final String label;
  final bool? value;

  const _BoolKV({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final text = v == null ? '—' : (v ? 'Yes' : 'No');
    return _KV(label: label, value: text);
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
