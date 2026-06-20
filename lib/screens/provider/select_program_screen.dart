import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class SelectProgramScreen extends StatelessWidget {
  const SelectProgramScreen({super.key});

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
                () => context.push('/record-test/malaria'),
              ),
              const SizedBox(height: 16),
              _buildProgramTile(
                context,
                HealthProgram.hiv,
                'Record HIV testing and counselling',
                Icons.favorite,
                () => context.push('/record-test/hiv'),
              ),
              const SizedBox(height: 16),
              _buildInterventionTile(
                context,
                label: 'PREVENTION MESSAGING',
                description: 'Record HIV/malaria prevention messaging session',
                icon: Icons.campaign,
                color: ProgramColors.preventionMessaging,
                onTap: () => context.push('/record-prevention-messaging'),
              ),
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
    return _buildInterventionTile(
      context,
      label: program.name.toUpperCase(),
      description: description,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }

  Widget _buildInterventionTile(
    BuildContext context, {
    required String label,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Text(
                      label,
                      style: context.textStyles.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
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
