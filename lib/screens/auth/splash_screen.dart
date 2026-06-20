import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/theme.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      final auth = context.read<AuthService>();
      if (auth.isAuthenticated) {
        context.go(auth.homeRouteForCurrentUser());
      } else {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) => const SplashScaffold();
}

/// Non-navigating splash UI scaffold (safe to show as an overlay).
class SplashScaffold extends StatelessWidget {
  const SplashScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: const SafeArea(child: SplashContent()),
    );
  }
}

class SplashContent extends StatelessWidget {
  const SplashContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Icon(Icons.health_and_safety, size: 100, color: Theme.of(context).colorScheme.onPrimary),
        const SizedBox(height: 24),
        Text(
          'MediFlow',
          style: context.textStyles.displaySmall?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: AppSpacing.horizontalLg,
          child: Text(
            'Health Commodity & Testing Platform',
            textAlign: TextAlign.center,
            style: context.textStyles.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
            ),
          ),
        ),
        const Spacer(),
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.onPrimary),
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}
