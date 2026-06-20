import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/fieldprovider_analytics_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/utils/ng_locations.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:provider/provider.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _loading = true;
  List<User> _users = const [];
  String _query = '';
  UserRole? _roleFilter;
  bool _mutating = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      if (!auth.isSuperAdminFull) {
        context.go('/admin/dashboard');
        return;
      }
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final auth = context.read<AuthService>();
      final users = await auth.listAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load admin users: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  List<User> get _filtered {
    final q = _query.trim().toLowerCase();
    return _users.where((u) {
      final matchesQuery = q.isEmpty ||
          u.username.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          (u.facilityName ?? '').toLowerCase().contains(q);
      final matchesRole = _roleFilter == null || u.role == _roleFilter;
      return matchesQuery && matchesRole;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final canManage = auth.isSuperAdminFull;

    void handleBack() {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        context.pop();
      } else {
        // If this screen was reached via context.go(), there may be nothing to pop.
        context.go('/provider-profile');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Approvals'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: handleBack),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/admin/dashboard'),
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Dashboard'),
          ),
          if (canManage)
            IconButton(
              tooltip: 'Create user',
              onPressed: _mutating ? null : _openCreateUserSheet,
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.paddingLg,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search users', hintText: 'Name, email, facility'),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<UserRole?>(
                          value: _roleFilter,
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_alt_outlined), labelText: 'Filter by role'),
                          items: [
                            const DropdownMenuItem<UserRole?>(value: null, child: Text('All roles')),
                            ...UserRole.values.map((r) => DropdownMenuItem<UserRole?>(value: r, child: Text(r.name))),
                          ],
                          onChanged: (v) => setState(() => _roleFilter = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? _AdminUsersLoadError(message: _loadError!, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: AppSpacing.paddingLg,
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final u = _filtered[index];
                                final knownPassword = auth.adminKnownPasswordFor(u.id);
                              return _UserRow(
                                user: u,
                                canManage: canManage,
                                  knownPassword: knownPassword,
                                onApprove: () async {
                                  if (_mutating) return;
                                  setState(() => _mutating = true);
                                  final ok = await auth.approveUser(u.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(ok ? 'Approved ${u.username}' : 'Approval failed')),
                                  );
                                  await _load();
                                  if (mounted) context.read<FieldProviderAnalyticsService>().invalidate();
                                  if (mounted) setState(() => _mutating = false);
                                },
                                onMakeViewOnly: () async {
                                  if (_mutating) return;
                                  setState(() => _mutating = true);
                                  final ok = await auth.setAdminScope(u.id, AdminScope.viewOnly);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Updated admin scope' : 'Update failed')));
                                  await _load();
                                  if (mounted) context.read<FieldProviderAnalyticsService>().invalidate();
                                  if (mounted) setState(() => _mutating = false);
                                },
                                onMakeFullAdmin: () async {
                                  if (_mutating) return;
                                  setState(() => _mutating = true);
                                  final ok = await auth.setAdminScope(u.id, AdminScope.full);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Updated admin scope' : 'Update failed')));
                                  await _load();
                                  if (mounted) context.read<FieldProviderAnalyticsService>().invalidate();
                                  if (mounted) setState(() => _mutating = false);
                                },
                                onRemoveAdmin: () async {
                                  if (_mutating) return;
                                  setState(() => _mutating = true);
                                  final ok = await auth.setAdminScope(u.id, AdminScope.none);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Updated admin scope' : 'Update failed')));
                                  await _load();
                                  if (mounted) context.read<FieldProviderAnalyticsService>().invalidate();
                                  if (mounted) setState(() => _mutating = false);
                                },
                                  onResetPassword: () => _confirmAndResetPassword(u),
                                onEdit: () => _openEditSheet(u),
                                onEditFieldProvider: u.role == UserRole.fieldProvider ? () => _openEditFieldProviderSheet(u) : null,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateUserSheet() async {
    if (_mutating) return;
    final auth = context.read<AuthService>();
    final rootMessenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final emailCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final orgCtrl = TextEditingController();
    UserRole role = UserRole.fieldProvider;
    ProviderType? providerType;
    AdminScope adminScope = AdminScope.none;
    var isCreating = false;
    String? inlineError;

    final created = await showModalBottomSheet<AdminCreatedUserCredentials>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final roleNeedsProviderType = role == UserRole.fieldProvider;

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create user', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('A password will be generated. Copy and send the credentials to the user.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.badge_outlined),
                        labelText: 'Username (login)',
                        hintText: 'e.g. amina_01',
                      ),
                      textInputAction: TextInputAction.next,
                      enabled: !isCreating,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: orgCtrl,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.apartment_outlined), labelText: 'Organization / Facility name'),
                      textInputAction: TextInputAction.next,
                      enabled: !isCreating,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined), labelText: 'Email (optional for FieldProvider)'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      enabled: !isCreating,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UserRole>(
                      value: role,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.person_pin_outlined), labelText: 'Role'),
                      items: UserRole.values.map((r) => DropdownMenuItem<UserRole>(value: r, child: Text(r.name))).toList(),
                      onChanged: isCreating
                          ? null
                          : (v) {
                            if (v == null) return;
                            setSheetState(() {
                              role = v;
                              if (role != UserRole.fieldProvider) providerType = null;
                              if (role == UserRole.superAdmin) adminScope = AdminScope.full;
                            });
                          },
                    ),
                    const SizedBox(height: 12),
                    if (roleNeedsProviderType) ...[
                      DropdownButtonFormField<ProviderType?>(
                        value: providerType,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.local_hospital_outlined), labelText: 'Provider type'),
                        items: [
                          const DropdownMenuItem<ProviderType?>(value: null, child: Text('Not set')),
                          ...ProviderType.values.map((t) => DropdownMenuItem<ProviderType?>(value: t, child: Text(t.name))),
                        ],
                        onChanged: isCreating ? null : (v) => setSheetState(() => providerType = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<AdminScope>(
                      value: adminScope,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.admin_panel_settings_outlined), labelText: 'Admin scope'),
                      items: AdminScope.values.map((s) => DropdownMenuItem<AdminScope>(value: s, child: Text(s.name))).toList(),
                      onChanged: isCreating
                          ? null
                          : (v) {
                            if (v == null) return;
                            setSheetState(() => adminScope = v);
                          },
                    ),
                    if (inlineError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
                        ),
                        child: Text(inlineError!, style: context.textStyles.bodySmall?.copyWith(color: scheme.onErrorContainer)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isCreating ? null : () => context.pop(null),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isCreating
                                ? null
                                : () async {
                                  final email = emailCtrl.text.trim();
                                  final username = usernameCtrl.text.trim();
                                  final org = orgCtrl.text.trim();
                                  final emailOk = email.isEmpty || email.contains('@');
                                  final usernameNorm = username.trim().toLowerCase();
                                  final usernameOk = username.isEmpty || RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(usernameNorm);

                                  if (org.isEmpty) {
                                    rootMessenger.showSnackBar(const SnackBar(content: Text('Please enter an organization/facility name.')));
                                    return;
                                  }

                                  if (!emailOk) {
                                    rootMessenger.showSnackBar(const SnackBar(content: Text('Please enter a valid email address.')));
                                    return;
                                  }

                                  if (!usernameOk) {
                                    rootMessenger.showSnackBar(const SnackBar(content: Text('Username must be 3-24 chars: letters, numbers, underscore, dot.')));
                                    return;
                                  }

                                  if (role == UserRole.fieldProvider) {
                                    if (email.isEmpty && username.isEmpty) {
                                      rootMessenger.showSnackBar(const SnackBar(content: Text('For FieldProvider, provide a username or an email (or both).')));
                                      return;
                                    }
                                  } else {
                                    if (email.isEmpty) {
                                      rootMessenger.showSnackBar(const SnackBar(content: Text('Email is required for this role.')));
                                      return;
                                    }
                                    if (username.isEmpty) {
                                      rootMessenger.showSnackBar(const SnackBar(content: Text('Username is required for this role.')));
                                      return;
                                    }
                                  }
                                  if (!mounted) return;
                                  setSheetState(() {
                                    isCreating = true;
                                    inlineError = null;
                                  });
                                  setState(() => _mutating = true);
                                  try {
                                    final creds = await auth.createUserAsAdmin(
                                      email: email.isEmpty ? null : email,
                                      username: username.isEmpty ? null : username,
                                      organizationName: org,
                                      role: role,
                                      adminScope: adminScope,
                                      providerType: providerType,
                                    );
                                    if (!context.mounted) return;
                                    if (creds == null || creds.password.isEmpty) {
                                      final raw = auth.lastAdminOperationError;
                                      final msg = (raw == null || raw.isEmpty) ? 'Could not create user. Please try again.' : raw;
                                      debugPrint('Create user failed: $msg');
                                      setSheetState(() => inlineError = msg);
                                      return;
                                    }
                                    context.pop(creds);
                                  } catch (e) {
                                    debugPrint('Create user UI handler failed: $e');
                                    if (!context.mounted) return;
                                    setSheetState(() => inlineError = e.toString());
                                  } finally {
                                    if (mounted) setState(() => _mutating = false);
                                    if (context.mounted) setSheetState(() => isCreating = false);
                                  }
                                },
                            icon: isCreating
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(isCreating ? 'Creating…' : 'Create'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Security: user will be forced to change password after first login.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted || created == null) return;
    await _showCreatedCredentialsDialog(created);
    await _load();
    if (mounted) context.read<FieldProviderAnalyticsService>().invalidate();
  }

  Future<void> _showCreatedCredentialsDialog(
    AdminCreatedUserCredentials creds, {
    String title = 'User created',
    String? subtitle,
    String? passwordLabel,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[];
    if (creds.username.trim().isNotEmpty) parts.add('Username: ${creds.username}');
    if (creds.email.trim().isNotEmpty) parts.add('Email: ${creds.email}');
    parts.add('Password: ${creds.password}');
    final text = parts.join('\n');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle ?? 'Copy these credentials and share them with the user.',
                style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (passwordLabel != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          passwordLabel,
                          style: context.textStyles.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SelectableText(text, style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: creds.username.trim().isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: creds.username));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username copied')));
                    },
              child: const Text('Copy username'),
            ),
            TextButton(
              onPressed: creds.email.trim().isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: creds.email));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email copied')));
                    },
              child: const Text('Copy email'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: creds.password));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
              },
              child: const Text('Copy password'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                context.pop();
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy all & Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmAndResetPassword(User user) async {
    if (_mutating) return;
    final auth = context.read<AuthService>();
    final scheme = Theme.of(context).colorScheme;

    final customCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var useCustom = false;
    String? inlineError;

    final res = await showModalBottomSheet<_ResetPasswordOptions>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reset password', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${user.username} • ${user.displayEmail}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          groupValue: useCustom,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setSheetState(() {
                            useCustom = v ?? false;
                            inlineError = null;
                          }),
                          title: const Text('Generate generic password (temporary)'),
                          subtitle: Text('We\'ll generate a secure temporary password and force change on next login.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          groupValue: useCustom,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setSheetState(() {
                            useCustom = v ?? false;
                            inlineError = null;
                          }),
                          title: const Text('Set custom password'),
                          subtitle: Text('Min 8 chars (recommended: include letters and numbers).', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                        if (useCustom) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: customCtrl,
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.password_outlined), labelText: 'Password'),
                            obscureText: true,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: confirmCtrl,
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.password_outlined), labelText: 'Confirm password'),
                            obscureText: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (inlineError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
                      ),
                      child: Text(inlineError!, style: context.textStyles.bodySmall?.copyWith(color: scheme.onErrorContainer)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => context.pop(null), child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            if (useCustom) {
                              final p = customCtrl.text.trim();
                              final c = confirmCtrl.text.trim();
                              if (p.isEmpty) {
                                setSheetState(() => inlineError = 'Enter a custom password (or choose generated).');
                                return;
                              }
                              if (p.length < 8) {
                                setSheetState(() => inlineError = 'Password must be at least 8 characters.');
                                return;
                              }
                              if (p != c) {
                                setSheetState(() => inlineError = 'Passwords do not match.');
                                return;
                              }
                            }
                            context.pop(_ResetPasswordOptions(customPassword: useCustom ? customCtrl.text.trim() : null));
                          },
                          icon: const Icon(Icons.lock_reset_outlined),
                          label: const Text('Reset'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Security: user will be forced to change password after first login.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              );
            },
          ),
        );
      },
    );

    if (res == null || !mounted) return;

    setState(() => _mutating = true);
    try {
      final creds = await auth.resetUserPasswordAsAdmin(userId: user.id, customPassword: res.customPassword);
      if (!mounted) return;

      if (creds == null || creds.password.isEmpty) {
        final raw = auth.lastAdminOperationError;
        final msg = (raw == null || raw.isEmpty) ? 'Could not reset password. Please try again.' : raw;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      // If the function didn’t return email for some reason, fall back to the profile email.
      final shown = AdminCreatedUserCredentials(
        userId: creds.userId,
        email: creds.email.isEmpty ? user.displayEmail : creds.email,
        authEmail: creds.authEmail,
        isSyntheticAuthEmail: creds.isSyntheticAuthEmail,
        username: creds.username.isEmpty ? user.username : creds.username,
        password: creds.password,
      );
      final usedCustom = res.customPassword != null && res.customPassword!.trim().isNotEmpty;
      await _showCreatedCredentialsDialog(
        shown,
        title: 'Password reset',
        subtitle: 'Share the new credentials with the user. This password will be shown only once in this dialog.',
        passwordLabel: usedCustom ? 'Custom password' : 'Temporary password (generated)',
      );
      await _load();
    } catch (e) {
      debugPrint('Reset password UI handler failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _openEditSheet(User user) async {
    if (_mutating) return;

    final auth = context.read<AuthService>();
    final scheme = Theme.of(context).colorScheme;

    var selectedRole = user.role;
    var selectedScope = user.adminScope;
    var selectedApproval = user.approvalStatus;

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Manage user', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${user.username} • ${user.displayEmail}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<UserApprovalStatus>(
                    value: selectedApproval,
                    decoration: const InputDecoration(labelText: 'Approval status', prefixIcon: Icon(Icons.verified_user_outlined)),
                    items: UserApprovalStatus.values
                        .map((s) => DropdownMenuItem<UserApprovalStatus>(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setSheetState(() => selectedApproval = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.badge_outlined)),
                    items: UserRole.values.map((r) => DropdownMenuItem<UserRole>(value: r, child: Text(r.name))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setSheetState(() => selectedRole = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AdminScope>(
                    value: selectedScope,
                    decoration: const InputDecoration(labelText: 'Admin scope', prefixIcon: Icon(Icons.admin_panel_settings_outlined)),
                    items: AdminScope.values.map((s) => DropdownMenuItem<AdminScope>(value: s, child: Text(s.name))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setSheetState(() => selectedScope = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.pop(true),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tip: “Admin scope: full” grants Super Admin permissions regardless of role.',
                    style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (res != true || !mounted) return;

    setState(() => _mutating = true);
    final ok = await auth.updateUserAsAdmin(
      userId: user.id,
      role: selectedRole,
      adminScope: selectedScope,
      approvalStatus: selectedApproval,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'User updated' : 'Update failed')));
    await _load();
    if (mounted) setState(() => _mutating = false);
  }

  Future<void> _openEditFieldProviderSheet(User user) async {
    if (_mutating) return;
    final auth = context.read<AuthService>();
    if (!auth.isSuperAdminFull) return;

    final scheme = Theme.of(context).colorScheme;

    final usernameCtrl = TextEditingController(text: user.username);
    final emailCtrl = TextEditingController(text: user.displayEmail);
    final facilityCtrl = TextEditingController(text: user.facilityName ?? '');
    final addressCtrl = TextEditingController(text: user.businessAddress ?? '');
    final contactEmailCtrl = TextEditingController(text: user.contactEmail ?? '');

    var selectedProviderType = user.providerType;
    var selectedState = (user.state ?? '').trim().isEmpty ? null : user.state;
    var selectedLga = (user.lga ?? '').trim().isEmpty ? null : user.lga;
    var selectedApproval = user.approvalStatus;

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final lgas = NgLocations.lgasForState(selectedState);
              if (selectedLga != null && lgas.isNotEmpty && !lgas.contains(selectedLga)) {
                selectedLga = null;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit Field Provider', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('Changes here are enforced server-side and audited.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                      helperText: 'Used for login. Changing it affects sign-in identifier.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.alternate_email),
                      helperText: 'Auth-linked. Changing it updates Supabase Auth + profile atomically.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Contact email (optional)',
                      prefixIcon: Icon(Icons.mark_email_read_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: facilityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Facility / Organization',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ProviderType?>(
                    value: selectedProviderType,
                    decoration: const InputDecoration(labelText: 'Provider type', prefixIcon: Icon(Icons.badge_outlined)),
                    items: [
                      const DropdownMenuItem<ProviderType?>(value: null, child: Text('Not set')),
                      ...ProviderType.values.map((t) => DropdownMenuItem<ProviderType?>(value: t, child: Text(t.name.toUpperCase()))),
                    ],
                    onChanged: (v) => setSheetState(() => selectedProviderType = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedState,
                    decoration: const InputDecoration(labelText: 'State', prefixIcon: Icon(Icons.map_outlined)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                      ...NgLocations.statesForRole('superAdmin').map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
                    ],
                    onChanged: (v) => setSheetState(() {
                      selectedState = v;
                      selectedLga = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedLga,
                    decoration: const InputDecoration(labelText: 'LGA (optional)', prefixIcon: Icon(Icons.location_on_outlined)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                      ...lgas.map((l) => DropdownMenuItem<String?>(value: l, child: Text(l))),
                    ],
                    onChanged: (v) => setSheetState(() => selectedLga = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Business address (optional)',
                      prefixIcon: Icon(Icons.home_work_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserApprovalStatus>(
                    value: selectedApproval,
                    decoration: const InputDecoration(labelText: 'Approval status', prefixIcon: Icon(Icons.verified_user_outlined)),
                    items: UserApprovalStatus.values
                        .map((s) => DropdownMenuItem<UserApprovalStatus>(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setSheetState(() => selectedApproval = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => context.pop(false), child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.pop(true),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );

    if (res != true || !mounted) return;

    setState(() => _mutating = true);
    try {
      final newUsername = usernameCtrl.text.trim();
      final newEmail = emailCtrl.text.trim();
      final newContact = contactEmailCtrl.text.trim();
      final newFacility = facilityCtrl.text.trim();
      final newAddress = addressCtrl.text.trim();

      final identityChanged = newUsername.toLowerCase() != user.username.trim().toLowerCase() || newEmail.toLowerCase() != user.displayEmail.trim().toLowerCase();
      final approvalChanged = selectedApproval != user.approvalStatus;

      User? updated;
      if (identityChanged || approvalChanged) {
        updated = await auth.updateFieldProviderIdentityAndStatusAsSuperAdmin(
          userId: user.id,
          username: newUsername,
          email: newEmail,
          approvalStatus: selectedApproval,
          state: selectedState,
          lga: selectedLga,
          facilityName: newFacility,
          providerType: selectedProviderType,
          businessAddress: newAddress,
          contactEmail: newContact.isEmpty ? null : newContact,
        );
      } else {
        updated = await auth.updateFieldProviderProfileAsSuperAdmin(
          userId: user.id,
          state: selectedState,
          lga: selectedLga,
          facilityName: newFacility,
          providerType: selectedProviderType,
          businessAddress: newAddress,
          contactEmail: newContact.isEmpty ? null : newContact,
        );
      }

      if (!mounted) return;
      if (updated == null) {
        final msg = auth.lastAdminOperationError ?? 'Update failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FieldProvider updated')));
      }
      await _load();
      if (mounted) context.read<FieldProviderAnalyticsService>().invalidate();
    } catch (e) {
      debugPrint('Edit FieldProvider UI handler failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _mutating = false);
      usernameCtrl.dispose();
      emailCtrl.dispose();
      facilityCtrl.dispose();
      addressCtrl.dispose();
      contactEmailCtrl.dispose();
    }
  }
}

class _UserRow extends StatelessWidget {
  final User user;
  final bool canManage;
  final String? knownPassword;
  final Future<void> Function() onApprove;
  final Future<void> Function() onMakeViewOnly;
  final Future<void> Function() onMakeFullAdmin;
  final Future<void> Function() onRemoveAdmin;
  final VoidCallback onResetPassword;
  final VoidCallback onEdit;
  final VoidCallback? onEditFieldProvider;

  const _UserRow({
    required this.user,
    required this.canManage,
    required this.knownPassword,
    required this.onApprove,
    required this.onMakeViewOnly,
    required this.onMakeFullAdmin,
    required this.onRemoveAdmin,
    required this.onResetPassword,
    required this.onEdit,
    required this.onEditFieldProvider,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPending = user.approvalStatus == UserApprovalStatus.pending;

    final subtitleParts = <String>[
      user.email,
      user.role.name,
      if (user.facilityName != null && user.facilityName!.trim().isNotEmpty) user.facilityName!,
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.person_outline, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.username, style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(subtitleParts.join(' • '), style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(user: user),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('Manage'),
                ),
                if (onEditFieldProvider != null)
                  OutlinedButton.icon(
                    onPressed: onEditFieldProvider,
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Edit profile'),
                  ),
                OutlinedButton.icon(
                  onPressed: onResetPassword,
                  icon: const Icon(Icons.lock_reset_outlined),
                  label: const Text('Reset password'),
                ),
                if (knownPassword != null && knownPassword!.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: knownPassword!));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
                    },
                    icon: Icon(Icons.copy_all_outlined, color: scheme.onSurfaceVariant),
                    label: Text('Copy password', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                if (isPending)
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Approve'),
                  ),
                OutlinedButton.icon(
                  onPressed: onMakeViewOnly,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Make Admin (View)'),
                ),
                OutlinedButton.icon(
                  onPressed: onMakeFullAdmin,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Make Super Admin'),
                ),
                TextButton.icon(
                  onPressed: onRemoveAdmin,
                  icon: Icon(Icons.remove_moderator_outlined, color: scheme.onSurfaceVariant),
                  label: Text('Remove Admin', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'View-only mode: you can review users, but only Super Admin can approve or change admin rights.',
              style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final User user;

  const _StatusPill({required this.user});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (bg, fg, text) = switch (user.approvalStatus) {
      UserApprovalStatus.approved => (scheme.tertiaryContainer, scheme.onTertiaryContainer, 'Approved'),
      UserApprovalStatus.pending => (scheme.secondaryContainer, scheme.onSecondaryContainer, 'Pending'),
      UserApprovalStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer, 'Rejected'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: context.textStyles.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w900)),
    );
  }
}

class _AdminUsersLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminUsersLoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: AppSpacing.paddingLg,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Could not load users',
                      style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: context.textStyles.bodySmall?.copyWith(color: scheme.onErrorContainer.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResetPasswordOptions {
  final String? customPassword;
  const _ResetPasswordOptions({required this.customPassword});
}
