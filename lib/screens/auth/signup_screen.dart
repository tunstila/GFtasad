import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _facilityController = TextEditingController();
  bool _obscurePassword = true;
  UserRole _selectedRole = UserRole.fieldProvider;
  ProviderType? _selectedProviderType;

  bool get _isFieldProvider => _selectedRole == UserRole.fieldProvider;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _facilityController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isFieldProvider && _selectedProviderType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select facility type')),
      );
      return;
    }

    final authService = context.read<AuthService>();
    final result = await authService.signup(
      _usernameController.text,
      _emailController.text,
      _passwordController.text,
      role: _selectedRole,
      facilityName: _facilityController.text,
      providerType: _isFieldProvider ? _selectedProviderType : null,
    );

    if (mounted) {
      if (result.ok) {
        switch (result.outcome) {
          case AuthSignupOutcome.successApproved:
            context.go(authService.homeRouteForCurrentUser());
            break;
          case AuthSignupOutcome.successPendingApproval:
            // Self-signup can still be configured as pending approval on the backend,
            // but the app no longer blocks sign-in purely on client-side approval flags.
            context.go('/login');
            break;
          case AuthSignupOutcome.successEmailConfirmationRequired:
            context.go('/pending-approval?mode=email');
            break;
          case AuthSignupOutcome.failed:
            break;
        }
      } else {
        final error = result.message ?? authService.lastSignupError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (error == null || error.trim().isEmpty)
                  ? 'Signup failed. If you previously signed up, try signing in or resetting your password.'
                  : error,
            ),
          ),
        );
      }
    }
  }

  String _providerTypeLabel(ProviderType type) {
    switch (type) {
      case ProviderType.chp:
        return 'Community Health Facility';
      case ProviderType.cp:
        return 'Community Pharmacy';
      case ProviderType.ppmv:
        return 'PPMV';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.paddingLg,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create Account',
                  style: context.textStyles.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Join the health commodity platform',
                  style: context.textStyles.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
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
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _facilityController,
                  decoration: const InputDecoration(
                    labelText: 'Facility / Organization',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your facility/organization name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Profile Type',
                  style: context.textStyles.titleMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.badge_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Provider account (self-signup). Admin accounts are created by Super Admin.',
                          style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _isFieldProvider
                      ? Padding(
                          key: const ValueKey('facilityType'),
                          padding: const EdgeInsets.only(top: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Facility Type', style: context.textStyles.titleMedium),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                children: ProviderType.values
                                    .map(
                                      (t) => ChoiceChip(
                                        label: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          child: Text(_providerTypeLabel(t)),
                                        ),
                                        selected: _selectedProviderType == t,
                                        onSelected: (selected) => setState(() => _selectedProviderType = selected ? t : null),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('none')),
                ),
                const SizedBox(height: 32),
                Consumer<AuthService>(
                  builder: (context, authService, _) => ElevatedButton(
                    onPressed: authService.isLoading ? null : _signup,
                    child: authService.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
