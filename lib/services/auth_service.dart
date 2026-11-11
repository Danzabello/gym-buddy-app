import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'nickname_service.dart';
import 'notification_service.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

/// The Web OAuth client, passed to google_sign_in as serverClientId so the ID
/// token's audience is the one Supabase's Google provider accepts. A client ID
/// is public; the client secret lives only in the Supabase dashboard.
const kGoogleWebClientId =
    '159614517589-07enhu2avringbf3fj21ggbiiub7easo.apps.googleusercontent.com';

const kGoogleSignInErrorMessage = 'Google sign-in did not work. Try again.';

enum GoogleSignInResult { success, cancelled, failed }

/// One Google sign-in attempt, with the plugin and Supabase injected so the
/// decision logic is testable. Never throws. A cancelled picker is
/// [GoogleSignInResult.cancelled]; a missing ID token, a Supabase error, no
/// network or a plugin error is [GoogleSignInResult.failed], and the Google
/// session is dropped so the next attempt starts clean. Logs the exception
/// code or type only, never a token, message or email.
Future<GoogleSignInResult> googleSignInFlow({
  required Future<String?> Function() pickIdToken,
  required Future<bool> Function(String idToken) exchange,
  required Future<void> Function() signOutGoogle,
}) async {
  var result = GoogleSignInResult.failed;
  try {
    final idToken = await pickIdToken();
    if (idToken != null && idToken.isNotEmpty && await exchange(idToken)) {
      result = GoogleSignInResult.success;
    }
  } on GoogleSignInException catch (e) {
    debugLog('Google sign-in ended: ${e.code.name}');
    if (e.code == GoogleSignInExceptionCode.canceled) {
      return GoogleSignInResult.cancelled;
    }
  } catch (e) {
    debugLog('Google sign-in failed: ${e.runtimeType}');
  }
  if (result == GoogleSignInResult.failed) {
    try {
      await signOutGoogle();
    } catch (_) {}
  }
  return result;
}

/// Supabase first, then Google, and Google even when Supabase throws: a
/// leftover Google session would skip the account picker next time.
Future<void> runSignOut({
  required Future<void> Function() supabaseSignOut,
  required Future<void> Function() googleSignOut,
}) async {
  try {
    await supabaseSignOut();
  } finally {
    await googleSignOut();
  }
}

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // google_sign_in must be initialised exactly once; a failed init may retry.
  static Future<void>? _googleInit;
  static Future<void> _ensureGoogleInit() => _googleInit ??= _initGoogle();
  static Future<void> _initGoogle() async {
    try {
      await GoogleSignIn.instance.initialize(serverClientId: kGoogleWebClientId);
    } catch (_) {
      _googleInit = null;
      rethrow;
    }
  }

  /// Google picker, then Supabase signInWithIdToken. The Google profile name
  /// and photo are never read: onboarding asks for those like for any user.
  Future<GoogleSignInResult> signInWithGoogle() => googleSignInFlow(
        pickIdToken: () async {
          await _ensureGoogleInit();
          final account = await GoogleSignIn.instance.authenticate();
          return account.authentication.idToken;
        },
        exchange: (idToken) async {
          final res = await _supabase.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
          );
          return res.user != null;
        },
        signOutGoogle: signOutGoogle,
      );

  /// Clears the Google session so the account picker shows again. Never
  /// throws (unsupported platform, not initialised): it must not block a
  /// sign-out.
  static Future<void> signOutGoogle() async {
    try {
      await _ensureGoogleInit();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugLog('Google sign-out failed: ${e.runtimeType}');
    }
  }

  // Sign up with email and password
  Future<String?> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        return null; // Success
      }
      return 'Sign up failed';
    } catch (e) {
      debugLog('AuthService.signUp failed: $e');
      return 'Sign up failed. Please try again.';
    }
  }

  // Sign in with email and password
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        return null; // Success
      }
      return 'Sign in failed';
    } catch (e) {
      debugLog('AuthService.signIn failed: $e');
      return 'Sign in failed. Please try again.';
    }
  }

  // Sign out
  Future<void> signOut() async {
    nicknameService.clearCache();
    // Must precede signOut(): removeToken() deletes by auth.uid().
    await NotificationService().removeToken();
    await runSignOut(
      supabaseSignOut: _supabase.auth.signOut,
      googleSignOut: signOutGoogle,
    );
  }

  // Get current user
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  // Check if user is signed in
  bool isSignedIn() {
    return _supabase.auth.currentUser != null;
  }

  // Send password reset email
  Future<String?> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      return null; // Success
    } catch (e) {
      debugLog('AuthService.resetPassword failed: $e');
      return 'Could not send reset email. Please try again.';
    }
  }

  // Safe way to get current user ID - throws if not authenticated
  // Use this instead of accessing currentUser directly in sensitive operations
  String requireAuthenticatedUserId() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    return userId;
  }

  /// DI-7 audit fix: a failed read must be distinguishable from "this account
  /// really never finished onboarding" (callers once treated `false` as
  /// orphaned and deleted). A successful read that finds no profile row is
  /// [OnboardingState.noProfile] (signed up, never finished); a failed read is
  /// [OnboardingState.unknown] and must never be treated as either.
  Future<OnboardingState> onboardingState(String userId) => readOnboardingState(
    () => _supabase.rpc('get_my_profile').select('onboarding_completed'),
  );
}

enum OnboardingState { complete, incomplete, noProfile, unknown }

/// Classifies one `get_my_profile` read. The read is taken as a list on
/// purpose: `single()` / `maybeSingle()` make PostgREST answer 406 for zero
/// rows, and the client only recognises that by its message text, so an
/// account with no profile looked like a failed read. An empty list is
/// [OnboardingState.noProfile]; anything thrown is [OnboardingState.unknown]
/// and must never be treated as "no profile" or "orphaned".
Future<OnboardingState> readOnboardingState(
  Future<List<Map<String, dynamic>>> Function() read,
) async {
  try {
    final rows = await read();
    if (rows.isEmpty) return OnboardingState.noProfile;
    return rows.first['onboarding_completed'] == true
        ? OnboardingState.complete
        : OnboardingState.incomplete;
  } catch (e) {
    debugLog('AuthService.onboardingState failed: $e');
    return OnboardingState.unknown;
  }
}
