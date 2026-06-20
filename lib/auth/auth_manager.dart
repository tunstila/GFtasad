// Authentication Manager - Base interface for auth implementations
//
// This abstract class and mixins define the contract for authentication systems.
// Implement this with concrete classes for Firebase, Supabase, or local auth.
//
// Usage:
// 1. Create a concrete class extending AuthManager
// 2. Mix in the required authentication provider mixins
// 3. Implement all abstract methods with your auth provider logic

import 'package:flutter/material.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Auth user type for the active auth provider (Supabase).
typedef AuthUser = sb.User;

// Core authentication operations that all auth implementations must provide
abstract class AuthManager {
  Future signOut();
  Future deleteUser(BuildContext context);
  Future updateEmail({required String email, required BuildContext context});
  Future resetPassword({required String email, required BuildContext context});

  /// Supabase does not require manual user refresh; the auth state stream updates.
  Future<void> refreshUser({required AuthUser user}) async {}

  /// In Supabase, email verification is handled by confirmation emails on signup
  /// (configurable in Supabase Auth settings).
  Future<void> sendEmailVerification({required AuthUser user}) async {}
}

// Email/password authentication mixin
mixin EmailSignInManager on AuthManager {
  Future<AuthUser?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  );

  Future<AuthUser?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  );
}

// Anonymous authentication for guest users
mixin AnonymousSignInManager on AuthManager {
  Future<AuthUser?> signInAnonymously(BuildContext context);
}

// Apple Sign-In authentication (iOS/web)
mixin AppleSignInManager on AuthManager {
  Future<AuthUser?> signInWithApple(BuildContext context);
}

// Google Sign-In authentication (all platforms)
mixin GoogleSignInManager on AuthManager {
  Future<AuthUser?> signInWithGoogle(BuildContext context);
}

// JWT token authentication for custom backends
mixin JwtSignInManager on AuthManager {
  Future<AuthUser?> signInWithJwtToken(
    BuildContext context,
    String jwtToken,
  );
}

// Phone number authentication with SMS verification
mixin PhoneSignInManager on AuthManager {
  Future beginPhoneAuth({
    required BuildContext context,
    required String phoneNumber,
    required void Function(BuildContext) onCodeSent,
  });

  Future verifySmsCode({
    required BuildContext context,
    required String smsCode,
  });
}

// Facebook Sign-In authentication
mixin FacebookSignInManager on AuthManager {
  Future<AuthUser?> signInWithFacebook(BuildContext context);
}

// Microsoft Sign-In authentication (Azure AD)
mixin MicrosoftSignInManager on AuthManager {
  Future<AuthUser?> signInWithMicrosoft(
    BuildContext context,
    List<String> scopes,
    String tenantId,
  );
}

// GitHub Sign-In authentication (OAuth)
mixin GithubSignInManager on AuthManager {
  Future<AuthUser?> signInWithGithub(BuildContext context);
}

/// Supabase email/password auth implementation.
///
/// Note: Deleting a user from Supabase requires admin privileges and is typically
/// done via an Edge Function using the service role key.
class SupabaseEmailAuthManager extends AuthManager with EmailSignInManager {
  @override
  Future<void> signOut() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('Supabase signOut failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteUser(BuildContext context) async {
    debugPrint('deleteUser is not supported from client-side Supabase anon key.');
    throw UnsupportedError(
      'Deleting a Supabase user must be done server-side (Edge Function) using the service role key.',
    );
  }

  @override
  Future<void> updateEmail({required String email, required BuildContext context}) async {
    try {
      await SupabaseConfig.auth.updateUser(sb.UserAttributes(email: email));
    } catch (e) {
      debugPrint('Supabase updateEmail failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> resetPassword({required String email, required BuildContext context}) async {
    try {
      await SupabaseConfig.auth.resetPasswordForEmail(email);
    } catch (e) {
      debugPrint('Supabase resetPassword failed: $e');
      rethrow;
    }
  }

  @override
  Future<AuthUser?> signInWithEmail(BuildContext context, String email, String password) async {
    try {
      final res = await SupabaseConfig.auth.signInWithPassword(email: email, password: password);
      return res.user;
    } catch (e) {
      debugPrint('Supabase signInWithEmail failed: $e');
      rethrow;
    }
  }

  @override
  Future<AuthUser?> createAccountWithEmail(BuildContext context, String email, String password) async {
    try {
      final res = await SupabaseConfig.auth.signUp(email: email, password: password);
      return res.user;
    } catch (e) {
      debugPrint('Supabase createAccountWithEmail failed: $e');
      rethrow;
    }
  }
}
