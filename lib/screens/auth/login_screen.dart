import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/notification_service.dart';
import 'package:mediflow/services/stock_alert_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/offline_banner.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isOffline = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = context.read<AuthService>();
    final result = await authService.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (mounted) {
      if (result.ok) {
        try {
          await Future.wait([
            context.read<TestRecordService>().initialize(),
            context.read<InventoryService>().initialize(),
            context.read<DeliveryService>().initialize(),
            context.read<NotificationService>().initialize(),
            context.read<StockAlertService>().initialize(),
          ]);
          final user = authService.currentUser;
          if (user?.hasGlobalView ?? false) {
            await context.read<TestRecordService>().syncAllForAdmin();
          }
        } catch (e) {
          debugPrint('Post-login data refresh failed (continuing): $e');
        }
        context.go(authService.homeRouteForCurrentUser());
      } else {
        final msg = switch (result.reason) {
          AuthLoginFailureReason.network => 'Network error: unable to reach the server. Please check your internet connection and try again.',
          AuthLoginFailureReason.invalidCredentials => 'Invalid email/username or password.',
          AuthLoginFailureReason.pendingApproval => 'Your account is pending approval.',
          AuthLoginFailureReason.emailNotConfirmed => 'Email not confirmed. Please check your inbox for the confirmation email (and spam/junk).',
          AuthLoginFailureReason.unknown => 'Login failed. ${result.details ?? ''}'.trim(),
          null => 'Login failed. Please try again.',
        };
        setState(() => _isOffline = result.reason == AuthLoginFailureReason.network);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OfflineBanner(isOffline: _isOffline),
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.paddingLg,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                      Icon(
                        Icons.health_and_safety,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome Back',
                        textAlign: TextAlign.center,
                        style: context.textStyles.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to continue',
                        textAlign: TextAlign.center,
                        style: context.textStyles.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 48),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username or Email',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your username or email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.push('/forgot-password'),
                          child: const Text('Forgot Password?'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Consumer<AuthService>(
                        builder: (context, authService, _) => ElevatedButton(
                          onPressed: authService.isLoading ? null : _login,
                          child: authService.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Sign In'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => context.push('/signup'),
                        child: const Text('Create Account'),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Version 1.0.0',
                          style: context.textStyles.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
