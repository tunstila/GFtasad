import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediflow/models/business_address.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/business_address_service.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

enum AuthSignupOutcome {
  successApproved,
  successPendingApproval,
  successEmailConfirmationRequired,
  failed,
}

enum AuthSignupFailureReason { timeout, network, emailAlreadyRegistered, weakPassword, invalidEmail, rlsDenied, unknown }

class AuthSignupResult {
  final AuthSignupOutcome outcome;
  final AuthSignupFailureReason? failureReason;
  final String? message;

  const AuthSignupResult._(this.outcome, this.failureReason, this.message);

  const AuthSignupResult.successApproved() : this._(AuthSignupOutcome.successApproved, null, null);
  const AuthSignupResult.successPendingApproval() : this._(AuthSignupOutcome.successPendingApproval, null, null);
  const AuthSignupResult.successEmailConfirmationRequired()
      : this._(AuthSignupOutcome.successEmailConfirmationRequired, null, null);

  const AuthSignupResult.failed(AuthSignupFailureReason reason, String message)
      : this._(AuthSignupOutcome.failed, reason, message);

  bool get ok => outcome != AuthSignupOutcome.failed;
}

enum AuthLoginFailureReason { network, invalidCredentials, pendingApproval, emailNotConfirmed, unknown }

class AuthLoginResult {
  final bool ok;
  final AuthLoginFailureReason? reason;
  final String? details;

  const AuthLoginResult._(this.ok, this.reason, this.details);

  const AuthLoginResult.success() : this._(true, null, null);
  const AuthLoginResult.network() : this._(false, AuthLoginFailureReason.network, null);
  const AuthLoginResult.invalidCredentials() : this._(false, AuthLoginFailureReason.invalidCredentials, null);
  const AuthLoginResult.pendingApproval() : this._(false, AuthLoginFailureReason.pendingApproval, null);
  const AuthLoginResult.emailNotConfirmed() : this._(false, AuthLoginFailureReason.emailNotConfirmed, null);
  const AuthLoginResult.unknown(String details) : this._(false, AuthLoginFailureReason.unknown, details);
}

class AuthService extends ChangeNotifier {
  static const String superAdminBootstrapEmail = 'tundeoyelana@gmail.com';

  static const Duration _signupStepTimeout = Duration(seconds: 30);

  static final RegExp _missingColumnRe = RegExp(r"Could not find the '([^']+)' column");

  User? _currentUser;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  bool get isSuperAdminView => _currentUser?.effectiveRole.hasGlobalView == true;
  bool get isSuperAdminFull => _currentUser?.effectiveRole == UserRole.superAdmin;

  String homeRouteForCurrentUser() {
    final user = _currentUser;
    if (user == null) return '/login';
    if (user.forcePasswordChange) return '/force-password-change';
    if (user.hasSuperAdminFull) return '/admin/users';
    if (user.hasGlobalView) return '/admin/dashboard';
    if (user.role == UserRole.nationalMalaria) return '/national/malaria';
    if (user.role == UserRole.nationalHIVTB) return '/national/hivtb';
    if (user.role == UserRole.supplier) return '/provider-home';
    return '/provider-home';
  }

  Future<UserAggregates> fetchUserAggregates() async {
    try {
      // Backend canonical column names vary across deployments (createdAt vs created_at).
      // Ordering is not required for aggregates, so avoid fragile orderBy fallbacks.
      final rows = await SupabaseService.select('users', select: 'role,state');
      final byRole = <String, int>{};
      final byState = <String, int>{};
      for (final r in rows) {
        final role = (r['role'] ?? 'unknown').toString();
        final state = (r['state'] ?? 'Unknown').toString();
        byRole[role] = (byRole[role] ?? 0) + 1;
        byState[state] = (byState[state] ?? 0) + 1;
      }
      final sortedByRole = Map<String, int>.fromEntries(byRole.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
      final sortedByState = Map<String, int>.fromEntries(byState.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
      return UserAggregates(total: rows.length, byRole: sortedByRole, byState: sortedByState);
    } catch (e) {
      debugPrint('Failed to fetch user aggregates: $e');
      rethrow;
    }
  }

  /// Admin-only: realtime stream of all user profiles.
  ///
  /// This requires your Supabase RLS policies to allow admin roles to select from `users`.
  Stream<List<User>> streamAllUsersForAdmin() {
    try {
      return SupabaseConfig.client.from('users').stream(primaryKey: ['id']).map((rows) => rows.map(_userFromDbRowFlexible).toList());
    } catch (e) {
      debugPrint('Failed to create users realtime stream: $e');
      return const Stream<List<User>>.empty();
    }
  }

  /// Lightweight result object so UI can show the correct failure reason.
  /// (Supabase often returns retryable network errors that can look like
  /// “invalid credentials” if we only show a generic snackbar.)
  AuthLoginResult? _lastLoginResult;
  AuthLoginResult? get lastLoginResult => _lastLoginResult;

  String? _lastSignupError;
  String? get lastSignupError => _lastSignupError;

  String? _lastAdminOperationError;
  String? get lastAdminOperationError => _lastAdminOperationError;

  void _setLastAdminOperationError(String? message) {
    _lastAdminOperationError = message;
    // Not calling notifyListeners() here because most callers just read it
    // immediately after awaiting an operation.
  }

  // Admin-only: ephemeral password visibility.
  // Passwords are NEVER persisted to your database; we only keep them in-memory
  // for the current app session so Super Admins can copy/share credentials.
  final Map<String, String> _adminKnownPasswordsByUserId = {};
  String? adminKnownPasswordFor(String userId) => _adminKnownPasswordsByUserId[userId];

  void _cacheAdminKnownPassword({required String userId, required String password}) {
    final id = userId.trim();
    final pwd = password.trim();
    if (id.isEmpty || pwd.isEmpty) return;
    _adminKnownPasswordsByUserId[id] = pwd;
    notifyListeners();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('currentUser');
      if (cached != null) {
        _currentUser = User.fromJson(jsonDecode(cached));
      }

      final authUser = SupabaseConfig.auth.currentUser;
      if (authUser != null) {
        // Best-effort: ensure backend schema additions (IDs/clients/batch fields) exist.
        try {
          await SupabaseConfig.client.functions.invoke('id_management', body: const {'action': 'ping'});
        } catch (e) {
          debugPrint('id_management ping failed (non-fatal): $e');
        }
        await _ensureProfileForAuthUser(authUser);
        final profile = await _fetchProfile(authUser.id);
        if (profile != null) {
          _currentUser = _applyBootstrapAdmin(profile);
          await _hydrateBusinessAddressForCurrentUser();
          await _cacheCurrentUser(_currentUser);
        }
      }
    } catch (e) {
      debugPrint('Failed to initialize auth: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AuthLoginResult> login(String usernameOrEmail, String password) async {
    _isLoading = true;
    _lastLoginResult = null;
    notifyListeners();

    try {
      // Secure pattern: do not resolve username->email client-side.
      // Always go through Edge Function so we don't leak account existence.
      final fnRes = await SupabaseConfig.client.functions.invoke(
        'sign_in_with_identifier',
        body: {
          'identifier': usernameOrEmail.trim(),
          'password': password,
        },
      );
      final fn = fnRes.data as Map?;
      if (fn?['ok'] != true) {
        throw Exception((fn?['error'] ?? 'Invalid credentials.').toString());
      }
      final session = (fn?['session'] as Map?) ?? const {};
      final refreshToken = (session['refresh_token'] ?? '').toString();
      if (refreshToken.isEmpty) throw Exception('Invalid credentials.');

      // Set session in the official client so all subsequent PostgREST calls use RLS-scoped JWT.
      final res = await SupabaseConfig.auth.setSession(refreshToken);
      final authUser = res.user;
      if (authUser == null) throw Exception('Login failed');

      await _ensureProfileForAuthUser(authUser);

      // Best-effort: ensure backend schema additions exist.
      try {
        await SupabaseConfig.client.functions.invoke('id_management', body: const {'action': 'ping'});
      } catch (e) {
        debugPrint('id_management ping failed (non-fatal): $e');
      }
      var profile = await _fetchProfile(authUser.id);
      profile ??= _fallbackUserFromAuth(authUser.id, authUser.email);
      if (profile == null) throw Exception('Profile not found. Please contact support.');

      final bootstrapped = _applyBootstrapAdmin(profile);

      _currentUser = bootstrapped.copyWith(lastLogin: DateTime.now(), updatedAt: DateTime.now());
      await _hydrateBusinessAddressForCurrentUser();
      await _cacheCurrentUser(_currentUser);

      // Ensure fieldprovider ID immediately after login (helps older accounts).
      if (_currentUser?.role == UserRole.fieldProvider && (_currentUser?.state ?? '').trim().isNotEmpty && (_currentUser?.fieldProviderUniqueId ?? '').trim().isEmpty) {
        try {
          final res = await SupabaseConfig.client.functions.invoke('id_management', body: const {'action': 'ensure_fieldprovider_id'});
          final data = res.data;
          final fpId = (data is Map) ? data['fieldProviderUniqueId']?.toString() : null;
          if (fpId != null && fpId.trim().isNotEmpty) {
            _currentUser = _currentUser!.copyWith(fieldProviderUniqueId: fpId.trim(), updatedAt: DateTime.now());
            await _cacheCurrentUser(_currentUser);
          }
        } catch (e) {
          debugPrint('Ensure fieldprovider id on login failed (non-fatal): $e');
        }
      }

      // Best-effort update of lastLogin/updatedAt.
      try {
        await _updateUserProfileFlexible(
          userId: _currentUser!.id,
          updates: {
            'lastLogin': _currentUser!.lastLogin,
            'updatedAt': _currentUser!.updatedAt,
          },
        );
      } catch (e) {
        debugPrint('Failed to update lastLogin: $e');
      }

      _lastLoginResult = const AuthLoginResult.success();
      return _lastLoginResult!;
    } catch (e) {
      debugPrint('Login failed: $e');

      final msg = e.toString();
      if (msg.contains('email_not_confirmed') || msg.toLowerCase().contains('email not confirmed')) {
        _lastLoginResult = const AuthLoginResult.emailNotConfirmed();
      } else if (msg.contains('Failed to fetch') || msg.contains('AuthRetryableFetchException')) {
        _lastLoginResult = const AuthLoginResult.network();
      } else if (msg.toLowerCase().contains('invalid login credentials') ||
          msg.toLowerCase().contains('invalid credentials')) {
        _lastLoginResult = const AuthLoginResult.invalidCredentials();
      } else {
        _lastLoginResult = AuthLoginResult.unknown(msg);
      }
      return _lastLoginResult!;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns:
  /// - structured result describing what happened (approved/pending/email confirm required/failure)
  Future<AuthSignupResult> signup(
    String username,
    String email,
    String password, {
    required UserRole role,
    String? facilityName,
    ProviderType? providerType,
    String? lga,
    String? state,
  }) async {
    _isLoading = true;
    _lastSignupError = null;
    notifyListeners();

    try {
      final normalizedEmail = email.trim();
      final normalizedUsername = username.trim();

      debugPrint('[signup] step=auth.signUp start email=$normalizedEmail');
      final signUpRes = await _retrySupabaseAuth(
        () => _withTimeout(
          SupabaseConfig.auth.signUp(
            email: normalizedEmail,
            password: password,
            data: {
              'username': normalizedUsername,
              'role': role.name,
              if (facilityName != null) 'facilityName': facilityName,
              if (providerType != null) 'providerType': providerType.name,
              if (lga != null) 'lga': lga,
              if (state != null) 'state': state,
            },
          ),
          step: 'auth.signUp',
        ),
      );
      debugPrint('[signup] step=auth.signUp done session=${signUpRes.session != null}');

      final authUser = signUpRes.user;
      if (authUser == null) throw Exception('Signup failed');

      // Important: if email confirmation is enabled on Supabase, signUp returns user
      // but no session. Without a session, PostgREST calls (insert/upsert profile)
      // will fail due to missing JWT. We still treat this as a successful signup.
      final emailConfirmationRequired = signUpRes.session == null;

      final now = DateTime.now();
      final isBootstrap = email.toLowerCase() == superAdminBootstrapEmail.toLowerCase();
      final adminScope = isBootstrap ? AdminScope.full : AdminScope.none;
      final approvalStatus = isBootstrap ? UserApprovalStatus.approved : UserApprovalStatus.pending;
      final normalizedRole = isBootstrap ? UserRole.superAdmin : role;

      if (!emailConfirmationRequired) {
        debugPrint('[signup] step=profile.upsert start userId=${authUser.id}');
        await _withTimeout(
          _upsertUserProfileFlexible(
            userId: authUser.id,
            username: normalizedUsername,
            email: normalizedEmail,
            role: normalizedRole,
            facilityName: facilityName,
            providerType: providerType,
            lga: lga,
            state: state,
            forcePasswordChange: true,
            approvalStatus: approvalStatus,
            approvedAt: isBootstrap ? now : null,
            approvedBy: isBootstrap ? authUser.id : null,
            adminScope: adminScope,
            createdAt: now,
            updatedAt: now,
          ),
          step: 'profile.upsert',
        );
        debugPrint('[signup] step=profile.upsert done');
      } else {
        debugPrint(
          '[signup] step=profile.upsert skipped (email confirmation required; no session yet)',
        );
      }

      // Notify super admins by email (edge function). Best-effort.
      try {
        debugPrint('[signup] step=edge.notify_pending_signup start');
        await _withTimeout(
          SupabaseConfig.client.functions.invoke(
            'admin_user_management',
            body: {
              'action': 'notify_pending_signup',
              'userId': authUser.id,
            },
          ),
          step: 'edge.notify_pending_signup',
          timeout: const Duration(seconds: 8),
        );
        debugPrint('[signup] step=edge.notify_pending_signup done');
      } catch (e) {
        debugPrint('Failed to notify super admin about signup request: $e');
      }

      if (emailConfirmationRequired) {
        // User must confirm email first; we can't reliably enforce approval gate
        // until the first real login (when a session exists).
        await _safeSignOutAfterSignup();
        return const AuthSignupResult.successEmailConfirmationRequired();
      }

      if (!isBootstrap) {
        // Enforce: user cannot proceed until approved.
        await _safeSignOutAfterSignup();
        return const AuthSignupResult.successPendingApproval();
      }

      // Bootstrap account can proceed immediately.
      final profile = await _fetchProfile(authUser.id);
      if (profile != null) {
        _currentUser = _applyBootstrapAdmin(profile);
        await _cacheCurrentUser(_currentUser);
      }
      return const AuthSignupResult.successApproved();
    } on TimeoutException catch (e) {
      debugPrint('Signup failed (timeout): $e');
      _lastSignupError = 'This is taking longer than expected. Please try again.';
      return const AuthSignupResult.failed(AuthSignupFailureReason.timeout, 'Signup timed out. Please try again.');
    } on sb.AuthException catch (e) {
      debugPrint('Signup failed (auth): ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('user already registered') || msg.contains('already registered')) {
        _lastSignupError = 'This email is already registered. Try signing in or resetting your password.';
        return const AuthSignupResult.failed(
          AuthSignupFailureReason.emailAlreadyRegistered,
          'This email is already registered. Try signing in or resetting your password.',
        );
      }
      if (msg.contains('password') && (msg.contains('weak') || msg.contains('at least'))) {
        _lastSignupError = 'Password is too weak. Please use a stronger password.';
        return const AuthSignupResult.failed(
          AuthSignupFailureReason.weakPassword,
          'Password is too weak. Please use a stronger password.',
        );
      }
      if (msg.contains('email') && (msg.contains('invalid') || msg.contains('format'))) {
        _lastSignupError = 'Please enter a valid email address.';
        return const AuthSignupResult.failed(AuthSignupFailureReason.invalidEmail, 'Please enter a valid email address.');
      }
      if (msg.contains('upstream request timeout') || msg.contains('504') || msg.contains('failed to fetch')) {
        _lastSignupError = 'Unable to reach the server right now. Please try again.';
        return const AuthSignupResult.failed(AuthSignupFailureReason.network, 'Unable to reach the server right now. Please try again.');
      }
      _lastSignupError = e.message;
      return AuthSignupResult.failed(AuthSignupFailureReason.unknown, e.message);
    } on sb.PostgrestException catch (e) {
      debugPrint('Signup failed (db): ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('row level security') || msg.contains('permission denied') || msg.contains('not allowed')) {
        _lastSignupError =
            'Account created, but profile setup was blocked by database security (RLS). Please contact the admin to update Supabase policies.';
        return const AuthSignupResult.failed(
          AuthSignupFailureReason.rlsDenied,
          'Account created, but profile setup was blocked by database security (RLS).',
        );
      }
      _lastSignupError = e.message;
      return AuthSignupResult.failed(AuthSignupFailureReason.unknown, e.message);
    } catch (e) {
      debugPrint('Signup failed: $e');
      final msg = e.toString();
      if (msg.contains('AuthRetryableFetchException') ||
          msg.contains('upstream request timeout') ||
          msg.contains('statusCode: 504') ||
          msg.contains('504')) {
        _lastSignupError = 'Unable to reach the server right now. Please try again.';
        return const AuthSignupResult.failed(AuthSignupFailureReason.network, 'Unable to reach the server right now. Please try again.');
      }
      if (msg.contains('over_email_send_rate_limit') || msg.toLowerCase().contains('rate limit')) {
        _lastSignupError = 'Email rate limit exceeded. Please wait a few minutes and try again.';
        return const AuthSignupResult.failed(AuthSignupFailureReason.unknown, 'Email rate limit exceeded. Please wait a few minutes and try again.');
      }
      if (msg.toLowerCase().contains('user already registered') || msg.toLowerCase().contains('already exists')) {
        _lastSignupError = 'This email is already registered. Try signing in or resetting your password.';
        return const AuthSignupResult.failed(
          AuthSignupFailureReason.emailAlreadyRegistered,
          'This email is already registered. Try signing in or resetting your password.',
        );
      }
      _lastSignupError = msg;
      return AuthSignupResult.failed(AuthSignupFailureReason.unknown, msg);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _safeSignOutAfterSignup() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('[signup] signOut failed (ignored): $e');
    }
    _currentUser = null;
    await _clearCachedUser();
  }

  Future<T> _withTimeout<T>(Future<T> future, {required String step, Duration? timeout}) async {
    final t = timeout ?? _signupStepTimeout;
    return future.timeout(
      t,
      onTimeout: () {
        debugPrint('[signup] step=$step TIMEOUT after ${t.inSeconds}s');
        throw TimeoutException('Timed out during $step', t);
      },
    );
  }

  Future<T> _retrySupabaseAuth<T>(Future<T> Function() op) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await op();
      } catch (e) {
        final msg = e.toString();
        final retryable =
            e is TimeoutException ||
            msg.contains('AuthRetryableFetchException') ||
            msg.contains('Failed to fetch') ||
            msg.contains('upstream request timeout') ||
            msg.contains('statusCode: 504') ||
            msg.contains('504');
        if (!retryable || attempt >= 3) rethrow;
        final delay = Duration(milliseconds: 700 * attempt * attempt);
        debugPrint('Retrying Supabase auth call (attempt $attempt) after ${delay.inMilliseconds}ms: $e');
        await Future.delayed(delay);
      }
    }
  }

  Future<void> logout() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('Supabase signOut failed: $e');
    }

    await _clearCachedUser();
    _currentUser = null;
    notifyListeners();
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    if (_currentUser == null) return false;

    try {
      // Re-auth by signing in again.
      await SupabaseConfig.auth.signInWithPassword(email: _currentUser!.email, password: currentPassword);
      await SupabaseConfig.auth.updateUser(sb.UserAttributes(password: newPassword));

      _currentUser = _currentUser!.copyWith(forcePasswordChange: false, updatedAt: DateTime.now());
      await _cacheCurrentUser(_currentUser);

      try {
        await _updateUserProfileFlexible(
          userId: _currentUser!.id,
          updates: {
            'forcePasswordChange': false,
            'updatedAt': _currentUser!.updatedAt,
          },
        );
      } catch (e) {
        debugPrint('Failed to update forcePasswordChange in profile: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Password change failed: $e');
      return false;
    }
  }

  Future<bool> updateBusinessProfile({
    required String businessAddress,
    String? ward,
    required String state,
    required String lga,
    double? latitude,
    double? longitude,
  }) async {
    final user = _currentUser;
    if (user == null) return false;

    final now = DateTime.now();
    try {
      await _updateUserProfileFlexible(
        userId: user.id,
        updates: {
          'state': state,
          'lga': lga,
          'businessAddress': businessAddress,
          'ward': (ward ?? '').trim().isEmpty ? null : ward!.trim(),
          'latitude': latitude,
          'longitude': longitude,
          'updatedAt': now,
        },
      );

      // Source of truth for address fields.
      await BusinessAddressService.upsert(
        BusinessAddress(
          userId: user.id,
          businessAddress: businessAddress,
          ward: (ward ?? '').trim().isEmpty ? null : ward!.trim(),
          state: state,
          lga: lga,
          latitude: latitude,
          longitude: longitude,
          createdAt: now,
          updatedAt: now,
        ),
      );

      _currentUser = user.copyWith(
        businessAddress: businessAddress,
        ward: (ward ?? '').trim().isEmpty ? null : ward!.trim(),
        state: state,
        lga: lga,
        latitude: latitude,
        longitude: longitude,
        updatedAt: now,
      );
      await _cacheCurrentUser(_currentUser);

      // If this is a FieldProvider and they now have a state, ensure they have a unique
      // state-scoped ID.
      if (_currentUser?.role == UserRole.fieldProvider && (_currentUser?.state ?? '').trim().isNotEmpty) {
        try {
          final res = await SupabaseConfig.client.functions.invoke('id_management', body: const {'action': 'ensure_fieldprovider_id'});
          final data = res.data;
          String? fpId;
          if (data is Map) fpId = data['fieldProviderUniqueId']?.toString();
          if (fpId != null && fpId.trim().isNotEmpty) {
            _currentUser = _currentUser!.copyWith(fieldProviderUniqueId: fpId.trim(), updatedAt: DateTime.now());
            await _cacheCurrentUser(_currentUser);
          }
        } catch (e) {
          debugPrint('Failed to ensure fieldProvider unique id (non-fatal): $e');
        }
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to update business profile: $e');
      return false;
    }
  }

  Future<void> _hydrateBusinessAddressForCurrentUser() async {
    final u = _currentUser;
    if (u == null) return;
    try {
      final addr = await BusinessAddressService.fetch(userId: u.id);
      if (addr == null) return;
      _currentUser = u.copyWith(
        businessAddress: addr.businessAddress,
        ward: addr.ward,
        state: addr.state.isEmpty ? u.state : addr.state,
        lga: addr.lga.isEmpty ? u.lga : addr.lga,
        latitude: addr.latitude,
        longitude: addr.longitude,
      );
    } catch (e) {
      debugPrint('Failed to hydrate business address: $e');
    }
  }

  Future<void> requestPasswordReset(String usernameOrEmail) async {
    try {
      final trimmed = usernameOrEmail.trim();
      if (!trimmed.contains('@')) {
        throw Exception('Username-only accounts cannot reset by email. Please contact your Admin/Super Admin to reset your password.');
      }
      await SupabaseConfig.auth.resetPasswordForEmail(trimmed.toLowerCase());
    } catch (e) {
      debugPrint('Password reset request failed: $e');
      rethrow;
    }
  }

  // ----------------------
  // Super admin operations
  // ----------------------

  Future<AdminCreatedUserCredentials?> createUserAsAdmin({
    String? email,
    String? username,
    required String organizationName,
    required UserRole role,
    AdminScope? adminScope,
    ProviderType? providerType,
    String? lga,
    String? state,
  }) async {
    _setLastAdminOperationError(null);
    try {
      // Fast reachability check (especially important on Flutter Web where
      // gateway/CORS issues surface as "Failed to fetch").
      await SupabaseConfig.client.functions
          .invoke('admin_user_management', body: const {'action': 'ping'})
          .timeout(const Duration(seconds: 10));

      final res = await SupabaseConfig.client.functions.invoke(
        'admin_user_management',
        body: {
          'action': 'create_user',
          if (email != null) 'email': email.trim(),
          if (username != null) 'username': username.trim(),
          'facilityName': organizationName.trim(),
          'role': role.name,
          if (adminScope != null) 'adminScope': adminScope.name,
          if (providerType != null) 'providerType': providerType.name,
          if (lga != null) 'lga': lga,
          if (state != null) 'state': state,
        },
      );

      final data = res.data as Map?;
      if (data?['ok'] != true) {
        final err = (data?['error'] ?? 'Unknown error').toString();
        _setLastAdminOperationError(err);
        debugPrint('Admin create user failed: $err');
        return null;
      }
      final creds = AdminCreatedUserCredentials(
        userId: (data?['userId'] ?? '').toString(),
        email: (data?['email'] ?? email ?? '').toString(),
        authEmail: (data?['authEmail'] ?? data?['auth_email'] ?? data?['email'] ?? '').toString(),
        isSyntheticAuthEmail: (data?['isSyntheticAuthEmail'] ?? data?['is_synthetic_auth_email'] ?? false) == true,
        username: (data?['username'] ?? username ?? '').toString(),
        password: (data?['password'] ?? '').toString(),
      );
      _cacheAdminKnownPassword(userId: creds.userId, password: creds.password);
      return creds;
    } catch (e) {
      String raw = e.toString();
      String? extracted;

      // Prefer structured edge-function errors when available.
      if (e is sb.FunctionException) {
        final details = e.details;
        if (details is Map) {
          final m = Map<String, dynamic>.from(details);
          final err = m['error']?.toString();
          final code = m['code']?.toString();
          final detailMsg = (m['details'] is Map)
              ? (Map<String, dynamic>.from(m['details'] as Map)['message']?.toString())
              : null;
          final composed = <String>[];
          if (err != null && err.trim().isNotEmpty) composed.add(err);
          if (detailMsg != null && detailMsg.trim().isNotEmpty) composed.add(detailMsg);
          if (composed.isNotEmpty) {
            extracted = (code != null && code.isNotEmpty) ? '${composed.join('\n')}\n($code)' : composed.join('\n');
          }
        }
        extracted ??= e.reasonPhrase;
        extracted ??= 'Request failed (HTTP ${e.status}).';
        raw = extracted;
      }

      final lower = raw.toLowerCase();

      final fnUrl = '${SupabaseConfig.supabaseUrl}/functions/v1/admin_user_management';
      final isFetchBlocked = lower.contains('failed to fetch') || (lower.contains('functions') && lower.contains('fetch'));
      final hint = isFetchBlocked
          ? "Couldn't reach the admin edge function (failed to fetch).\n\nMost common causes on Web:\n• Supabase gateway is blocking the request (verify_jwt)\n• Missing/incorrect CORS headers (including OPTIONS preflight)\n• Function is deployed to a different Supabase project than this app is configured to use\n\nChecks:\n1) Ensure `lib/supabase/config.toml` contains:\n   [functions.admin_user_management]\n   enabled = true\n   verify_jwt = false\n2) Confirm this URL is valid for your current Supabase project:\n   $fnUrl\n3) Redeploy the function after changing config/code."
          : raw;
      _setLastAdminOperationError(hint);
      debugPrint('Failed to create user as admin: $raw');
      return null;
    }
  }

  Future<AdminCreatedUserCredentials?> resetUserPasswordAsAdmin({required String userId, String? customPassword}) async {
    _setLastAdminOperationError(null);
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'admin_user_management',
        body: {
          'action': 'reset_password',
          'userId': userId,
          if (customPassword != null && customPassword.trim().isNotEmpty) 'customPassword': customPassword.trim(),
        },
      );

      final data = res.data as Map?;
      if (data?['ok'] != true) {
        final err = (data?['error'] ?? 'Unknown error').toString();
        _setLastAdminOperationError(err);
        debugPrint('Admin reset password failed: $err');
        return null;
      }

      final creds = AdminCreatedUserCredentials(
        userId: (data?['userId'] ?? userId).toString(),
        email: (data?['email'] ?? '').toString(),
        authEmail: (data?['authEmail'] ?? data?['auth_email'] ?? data?['email'] ?? '').toString(),
        isSyntheticAuthEmail: (data?['isSyntheticAuthEmail'] ?? data?['is_synthetic_auth_email'] ?? false) == true,
        username: (data?['username'] ?? '').toString(),
        password: (data?['password'] ?? '').toString(),
      );
      _cacheAdminKnownPassword(userId: creds.userId, password: creds.password);
      return creds;
    } catch (e) {
      String raw = e.toString();

      if (e is sb.FunctionException) {
        final details = e.details;
        if (details is Map) {
          final m = Map<String, dynamic>.from(details);
          final err = m['error']?.toString();
          final code = m['code']?.toString();
          if (err != null && err.trim().isNotEmpty) {
            raw = (code != null && code.isNotEmpty) ? '$err\n($code)' : err;
          }
        }
        raw = e.reasonPhrase ?? raw;
      }

      _setLastAdminOperationError(raw);
      debugPrint('Failed to reset user password as admin: $raw');
      return null;
    }
  }

  // ------------------------------------------------------------
  // Super Admin: FieldProvider edit operations (backend-enforced)
  // ------------------------------------------------------------

  /// Profile-only edits (no auth identity or approval side effects).
  ///
  /// Backend source of truth: `public.admin_update_fieldprovider_profile` RPC.
  Future<User?> updateFieldProviderProfileAsSuperAdmin({
    required String userId,
    String? state,
    String? lga,
    String? facilityName,
    ProviderType? providerType,
    String? businessAddress,
    String? contactEmail,
    double? latitude,
    double? longitude,
  }) async {
    if (!isSuperAdminFull) return null;
    _setLastAdminOperationError(null);
    try {
      final patch = <String, dynamic>{
        if (state != null) 'state': state,
        if (lga != null) 'lga': lga,
        if (facilityName != null) 'facilityName': facilityName,
        if (providerType != null) 'providerType': providerType.name,
        if (businessAddress != null) 'businessAddress': businessAddress,
        if (contactEmail != null) 'contactEmail': contactEmail,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

      final res = await SupabaseConfig.client.rpc(
        'admin_update_fieldprovider_profile',
        params: {'target_user_id': userId, 'patch': patch},
      );
      if (res == null) return null;
      if (res is! Map) return null;
      return _userFromDbRowFlexible(Map<String, dynamic>.from(res));
    } catch (e) {
      debugPrint('updateFieldProviderProfileAsSuperAdmin failed: $e');
      _setLastAdminOperationError(e.toString());
      return null;
    }
  }

  /// Identity/approval edits (username/email/approvalStatus) OR mixed edits.
  ///
  /// Backend source of truth: `admin_update_fieldprovider` Edge Function.
  Future<User?> updateFieldProviderIdentityAndStatusAsSuperAdmin({
    required String userId,
    String? username,
    String? email,
    UserApprovalStatus? approvalStatus,
    String? state,
    String? lga,
    String? facilityName,
    ProviderType? providerType,
    String? businessAddress,
    String? contactEmail,
    double? latitude,
    double? longitude,
  }) async {
    if (!isSuperAdminFull) return null;
    _setLastAdminOperationError(null);
    try {
      final patch = <String, dynamic>{
        if (username != null) 'username': username.trim(),
        if (email != null) 'email': email.trim(),
        if (approvalStatus != null) 'approvalStatus': approvalStatus.name,
        if (state != null) 'state': state,
        if (lga != null) 'lga': lga,
        if (facilityName != null) 'facilityName': facilityName,
        if (providerType != null) 'providerType': providerType.name,
        if (businessAddress != null) 'businessAddress': businessAddress,
        if (contactEmail != null) 'contactEmail': contactEmail,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

      final res = await SupabaseConfig.client.functions.invoke(
        'admin_update_fieldprovider',
        body: {'targetUserId': userId, 'patch': patch},
      );

      final data = res.data as Map?;
      if (data?['ok'] != true) {
        final err = (data?['error'] ?? 'Update failed').toString();
        _setLastAdminOperationError(err);
        debugPrint('admin_update_fieldprovider failed: $err');
        return null;
      }

      final user = data?['user'];
      if (user is Map) return _userFromDbRowFlexible(Map<String, dynamic>.from(user));
      return null;
    } catch (e) {
      String raw = e.toString();
      if (e is sb.FunctionException) {
        final details = e.details;
        if (details is Map) {
          final m = Map<String, dynamic>.from(details);
          final err = m['error']?.toString();
          if (err != null && err.trim().isNotEmpty) raw = err;
        }
        raw = raw.isEmpty ? (e.reasonPhrase ?? 'Request failed (HTTP ${e.status}).') : raw;
      }
      _setLastAdminOperationError(raw);
      debugPrint('updateFieldProviderIdentityAndStatusAsSuperAdmin failed: $raw');
      return null;
    }
  }

  Future<List<User>> listAllUsers() async {
    _setLastAdminOperationError(null);
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'admin_user_management',
        body: {'action': 'list_users'},
      );

      final data = (res.data as Map?)?['users'];
      if (data is List) {
        try {
          return List<User>.from(data.map((e) => User.fromJson(Map<String, dynamic>.from(e))));
        } catch (e) {
          debugPrint('Edge list_users returned rows that could not be parsed; falling back to direct DB read: $e');
        }
      }

      // Fallback: direct read (requires RLS policy that allows this for super admins).
      final rows = await SupabaseService.select('users');
      return rows.map(_userFromDbRowFlexible).toList();
    } catch (e) {
      debugPrint('Failed to list users via edge function; falling back to direct DB read: $e');
      try {
        final rows = await SupabaseService.select('users');
        return rows.map(_userFromDbRowFlexible).toList();
      } catch (e2) {
        debugPrint('Failed to list users via direct DB read: $e2');
        return [];
      }
    }
  }

  User _userFromDbRowFlexible(Map<String, dynamic> row) {
    final nowIso = DateTime.now().toIso8601String();
    return User.fromJson({
      'id': row['id'],
      'username': row['username'] ?? row['full_name'] ?? row['fullName'] ?? 'Unknown',
      'email': row['email'] ?? '',
      'role': row['role'] ?? 'fieldProvider',
      'facilityName': row['facilityName'] ?? row['facility_name'],
      'providerType': row['providerType'] ?? row['provider_type'],
      'lga': row['lga'],
      'state': row['state'],
      'fieldProviderUniqueId': row['fieldProviderUniqueId'] ?? row['fieldprovideruniqueid'] ?? row['field_provider_unique_id'] ?? row['fieldproviderid'] ?? row['field_provider_id'],
      'forcePasswordChange': row['forcePasswordChange'] ?? row['force_password_change'] ?? false,
      'lastLogin': row['lastLogin'] ?? row['last_login'],
      'approvalStatus': row['approvalstatus'] ?? row['approvalStatus'] ?? row['approval_status'] ?? 'approved',
      'approvedAt': row['approvedAt'] ?? row['approved_at'],
      'approvedBy': row['approvedBy'] ?? row['approved_by'],
      'adminScope': row['adminScope'] ?? row['admin_scope'],
      'createdAt': row['createdAt'] ?? row['created_at'] ?? nowIso,
      'updatedAt': row['updatedAt'] ?? row['updated_at'] ?? nowIso,
    });
  }

  Future<bool> approveUser(String userId) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'admin_user_management',
        body: {'action': 'approve_user', 'userId': userId},
      );
      return (res.data as Map?)?['ok'] == true;
    } catch (e) {
      debugPrint('Failed to approve user: $e');
      return false;
    }
  }

  Future<bool> setAdminScope(String userId, AdminScope scope) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'admin_user_management',
        body: {'action': 'set_admin_scope', 'userId': userId, 'adminScope': scope.name},
      );
      return (res.data as Map?)?['ok'] == true;
    } catch (e) {
      debugPrint('Failed to set admin scope: $e');
      return false;
    }
  }

  Future<bool> updateUserAsAdmin({
    required String userId,
    UserRole? role,
    AdminScope? adminScope,
    UserApprovalStatus? approvalStatus,
  }) async {
    try {
      final body = <String, dynamic>{
        'action': 'update_user',
        'userId': userId,
        if (role != null) 'role': role.name,
        if (adminScope != null) 'adminScope': adminScope.name,
        if (approvalStatus != null) 'approvalStatus': approvalStatus.name,
      };

      final res = await SupabaseConfig.client.functions.invoke('admin_user_management', body: body);
      return (res.data as Map?)?['ok'] == true;
    } catch (e) {
      debugPrint('Failed to update user as admin: $e');
      return false;
    }
  }

  // ----------------------
  // Internal helpers
  // ----------------------

  User _applyBootstrapAdmin(User u) {
    if (u.email.toLowerCase() == superAdminBootstrapEmail.toLowerCase()) {
      return u.copyWith(adminScope: AdminScope.full, approvalStatus: UserApprovalStatus.approved);
    }
    return u;
  }

  User? _fallbackUserFromAuth(String userId, String? emailRaw) {
    final email = (emailRaw ?? '').trim();
    if (email.isEmpty) return null;
    final now = DateTime.now();
    final isBootstrap = email.toLowerCase() == superAdminBootstrapEmail.toLowerCase();
    return User(
      id: userId,
      username: email.contains('@') ? email.split('@').first : email,
      name: null,
      email: email,
      role: isBootstrap ? UserRole.superAdmin : UserRole.fieldProvider,
      approvalStatus: isBootstrap ? UserApprovalStatus.approved : UserApprovalStatus.pending,
      adminScope: isBootstrap ? AdminScope.full : AdminScope.none,
      facilityName: isBootstrap ? 'Super Admin' : 'Unknown Facility',
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _cacheCurrentUser(User? user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        await prefs.remove('currentUser');
      } else {
        await prefs.setString('currentUser', jsonEncode(user.toJson()));
      }
    } catch (e) {
      debugPrint('Failed to cache user: $e');
    }
  }

  Future<void> _clearCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('currentUser');
    } catch (e) {
      debugPrint('Failed to clear cached user: $e');
    }
  }

  Future<User?> _fetchProfile(String userId) async {
    try {
      final row = await SupabaseService.selectSingle('users', filters: {'id': userId});
      if (row == null) return null;

      T? pick<T>(String camel, String snake) {
        final v = row[camel] ?? row[snake];
        return v is T ? v : null;
      }

      final normalized = <String, dynamic>{
        'id': row['id'],
        'name': row['name'] ?? row['full_name'] ?? row['fullName'],
        'username': pick<String>('username', 'username'),
        'email': pick<String>('email', 'email'),
        'role': pick<String>('role', 'role'),
        'facilityName': row['facilityName'] ?? row['facility_name'],
        'providerType': row['providerType'] ?? row['provider_type'],
        'lga': row['lga'],
        'state': row['state'],
        'forcePasswordChange': row['forcePasswordChange'] ?? row['force_password_change'] ?? false,
        'lastLogin': row['lastLogin'] ?? row['last_login'],
        'approvalStatus': row['approvalStatus'] ?? row['approval_status'],
        'approvedAt': row['approvedAt'] ?? row['approved_at'],
        'approvedBy': row['approvedBy'] ?? row['approved_by'],
        'adminScope': row['adminScope'] ?? row['admin_scope'],
        'createdAt': row['createdAt'] ?? row['created_at'],
        'updatedAt': row['updatedAt'] ?? row['updated_at'],
      };
      return User.fromJson(normalized);
    } catch (e) {
      debugPrint('Failed to fetch profile: $e');
      return null;
    }
  }

  Future<void> _ensureProfileForAuthUser(sb.User authUser) async {
    try {
      final String userId = authUser.id;
      final existing = await SupabaseService.selectSingle('users', filters: {'id': userId});
      if (existing != null) return;

      final email = (authUser.email ?? '').trim();
      if (email.isEmpty) return;

      final meta = Map<String, dynamic>.from(authUser.userMetadata ?? const <String, dynamic>{});
      final metaUsername = meta['username'];
      final metaRole = meta['role'];
      final metaFacilityName = meta['facilityName'];
      final metaProviderType = meta['providerType'];
      final metaLga = meta['lga'];
      final metaState = meta['state'];

      final now = DateTime.now();
      final isBootstrap = email.toLowerCase() == superAdminBootstrapEmail.toLowerCase();
      final username = (metaUsername is String && metaUsername.trim().isNotEmpty)
          ? metaUsername.trim()
          : (email.contains('@') ? email.split('@').first : email);

      UserRole inferredRole = isBootstrap ? UserRole.superAdmin : UserRole.fieldProvider;
      if (!isBootstrap && metaRole is String) {
        inferredRole = UserRole.values.firstWhere(
          (r) => r.name == metaRole,
          orElse: () => UserRole.fieldProvider,
        );
      }

      ProviderType? providerType;
      if (metaProviderType is String) {
        try {
          providerType = ProviderType.values.firstWhere((t) => t.name == metaProviderType);
        } catch (_) {
          providerType = null;
        }
      }

      await _upsertUserProfileFlexible(
        userId: userId,
        username: username,
        email: email,
        role: inferredRole,
        facilityName: (metaFacilityName is String && metaFacilityName.trim().isNotEmpty)
            ? metaFacilityName.trim()
            : (isBootstrap ? 'Super Admin' : 'Unknown Facility'),
        providerType: providerType,
        lga: metaLga is String ? metaLga : null,
        state: metaState is String ? metaState : null,
        forcePasswordChange: false,
        approvalStatus: isBootstrap ? UserApprovalStatus.approved : UserApprovalStatus.pending,
        approvedAt: isBootstrap ? now : null,
        approvedBy: isBootstrap ? userId : null,
        adminScope: isBootstrap ? AdminScope.full : AdminScope.none,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      debugPrint('Failed to ensure profile for auth user: $e');
    }
  }

  // ----------------------
  // Schema-flex helpers
  // ----------------------

  Future<void> _upsertUserProfileFlexible({
    required String userId,
    required String username,
    required String email,
    required UserRole role,
    required String? facilityName,
    required ProviderType? providerType,
    required String? lga,
    required String? state,
    required bool forcePasswordChange,
    required UserApprovalStatus approvalStatus,
    required DateTime? approvedAt,
    required String? approvedBy,
    required AdminScope adminScope,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final camel = <String, dynamic>{
      'id': userId,
      'username': username,
      'email': email,
      'role': role.name,
      'facilityName': facilityName,
      'providerType': providerType?.name,
      'lga': lga,
      'state': state,
      'forcePasswordChange': forcePasswordChange,
      'approvalStatus': approvalStatus.name,
      'approvedAt': approvedAt?.toIso8601String(),
      'approvedBy': approvedBy,
      'adminScope': adminScope.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };

    final snake = <String, dynamic>{
      'id': userId,
      'username': username,
      'email': email,
      'role': role.name,
      'facility_name': facilityName,
      'provider_type': providerType?.name,
      'lga': lga,
      'state': state,
      'force_password_change': forcePasswordChange,
      'approval_status': approvalStatus.name,
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by': approvedBy,
      'admin_scope': adminScope.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    try {
      await _resilientUpsert('users', camel, onConflict: 'id');
    } catch (e) {
      final msg = e.toString();
      final looksLikeColumnMismatch = msg.contains('schema cache') || msg.contains("Could not find the '");
      if (!looksLikeColumnMismatch) rethrow;
      debugPrint('Upsert failed with camelCase columns, retrying with snake_case: $msg');
      await _resilientUpsert('users', snake, onConflict: 'id');
    }
  }

  Future<void> _updateUserProfileFlexible({required String userId, required Map<String, dynamic> updates}) async {
    Map<String, dynamic> camel = <String, dynamic>{};
    Map<String, dynamic> snake = <String, dynamic>{};

    if (updates.containsKey('lastLogin')) {
      final v = updates['lastLogin'];
      final iso = v is DateTime ? v.toIso8601String() : null;
      camel['lastLogin'] = iso;
      snake['last_login'] = iso;
    }
    if (updates.containsKey('updatedAt')) {
      final v = updates['updatedAt'];
      final iso = v is DateTime ? v.toIso8601String() : DateTime.now().toIso8601String();
      camel['updatedAt'] = iso;
      snake['updated_at'] = iso;
    }
    if (updates.containsKey('forcePasswordChange')) {
      final v = updates['forcePasswordChange'];
      camel['forcePasswordChange'] = v;
      snake['force_password_change'] = v;
    }

    if (updates.containsKey('businessAddress')) {
      final v = updates['businessAddress'];
      camel['businessAddress'] = v;
      snake['business_address'] = v;
    }
    if (updates.containsKey('state')) {
      final v = updates['state'];
      camel['state'] = v;
      snake['state'] = v;
    }
    if (updates.containsKey('lga')) {
      final v = updates['lga'];
      camel['lga'] = v;
      snake['lga'] = v;
    }
    if (updates.containsKey('latitude')) {
      final v = updates['latitude'];
      camel['latitude'] = v;
      snake['latitude'] = v;
    }
    if (updates.containsKey('longitude')) {
      final v = updates['longitude'];
      camel['longitude'] = v;
      snake['longitude'] = v;
    }

    try {
      await _resilientUpdate('users', camel, filters: {'id': userId});
    } catch (e) {
      final msg = e.toString();
      final looksLikeColumnMismatch = msg.contains('schema cache') || msg.contains("Could not find the '");
      if (!looksLikeColumnMismatch) rethrow;
      debugPrint('Update failed with camelCase columns, retrying with snake_case: $msg');
      await _resilientUpdate('users', snake, filters: {'id': userId});
    }
  }

  Future<void> _resilientUpsert(String table, Map<String, dynamic> data, {String? onConflict}) async {
    final working = Map<String, dynamic>.from(data)..removeWhere((k, v) => v == null);
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        await SupabaseService.upsert(table, working, onConflict: onConflict);
        return;
      } catch (e) {
        final msg = e.toString();
        final m = _missingColumnRe.firstMatch(msg);
        final missing = m?.group(1);
        if (missing == null || !working.containsKey(missing) || attempt >= 10) rethrow;
        debugPrint('Supabase schema mismatch: removing missing column "$missing" and retrying');
        working.remove(missing);
      }
    }
  }

  Future<void> _resilientUpdate(String table, Map<String, dynamic> data, {required Map<String, dynamic> filters}) async {
    final working = Map<String, dynamic>.from(data)..removeWhere((k, v) => v == null);
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        await SupabaseService.update(table, working, filters: filters);
        return;
      } catch (e) {
        final msg = e.toString();
        final m = _missingColumnRe.firstMatch(msg);
        final missing = m?.group(1);
        if (missing == null || !working.containsKey(missing) || attempt >= 10) rethrow;
        debugPrint('Supabase schema mismatch: removing missing column "$missing" and retrying');
        working.remove(missing);
      }
    }
  }
}

class AdminCreatedUserCredentials {
  final String userId;
  /// Contact email (safe to show). May be empty for username-only accounts.
  final String email;

  /// Internal auth email used by Supabase auth (may be synthetic).
  final String authEmail;

  final bool isSyntheticAuthEmail;

  final String username;
  final String password;

  const AdminCreatedUserCredentials({required this.userId, required this.email, required this.authEmail, required this.isSyntheticAuthEmail, required this.username, required this.password});
}

class UserAggregates {
  final int total;
  final Map<String, int> byRole;
  final Map<String, int> byState;

  const UserAggregates({required this.total, required this.byRole, required this.byState});
}
