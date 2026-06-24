import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/program_badge.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class SelectProgramScreen extends StatelessWidget {
  const SelectProgramScreen({super.key});

  Future<void> _guardAndNavigate(BuildContext context, String route) async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final mustGate = user?.role.name == 'fieldProvider' && user?.hasCompleteBusinessLocation != true;

    if (!mustGate) {
      context.push(route);
      return;
    }

    if (!context.mounted) return;
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.location_off_outlined, color: scheme.error),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Business profile required', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Please complete your Business Profile State, LGA, and Ward before recording tests.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/provider-profile/address');
                },
                icon: Icon(Icons.location_on_outlined, color: scheme.onPrimary),
                label: Text('Go to Profile → Business', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Health Program'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Choose a program to record test',
                style: context.textStyles.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildProgramTile(
                context,
                HealthProgram.malaria,
                'Record malaria rapid diagnostic test and treatment',
                Icons.bug_report,
                () => _guardAndNavigate(context, '/record-test/malaria'),
              ),
              const SizedBox(height: 16),
              _buildProgramTile(
                context,
                HealthProgram.hiv,
                'Record HIV testing and counselling',
                Icons.favorite,
                () => _guardAndNavigate(context, '/record-test/hiv'),
              ),
              const SizedBox(height: 16),
              _buildPreventionMessagingTile(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgramTile(
    BuildContext context,
    HealthProgram program,
    String description,
    IconData icon,
    VoidCallback onTap,
  ) {
    final color = _getProgramColor(program);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProgramBadge(program: program),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPreventionMessagingTile(BuildContext context) {
    final color = ProgramColors.prevention;
    return GestureDetector(
      onTap: () => _guardAndNavigate(context, '/record-prevention-messaging'),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.campaign, color: color, size: 36),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Text(
                      'PREVENTION MESSAGING',
                      style: context.textStyles.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Record prevention education and referral services',
                    style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Color _getProgramColor(HealthProgram program) {
    switch (program) {
      case HealthProgram.malaria:
        return ProgramColors.malaria;
      case HealthProgram.hiv:
        return ProgramColors.hiv;
      case HealthProgram.tb:
        return ProgramColors.tb;
    }
  }
}
