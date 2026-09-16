import 'package:supabase_flutter/supabase_flutter.dart';
import 'nickname_service.dart';
import 'notification_service.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
    await _supabase.auth.signOut();
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

  // DI-7 audit fix: was duplicated verbatim in main.dart and login_screen.dart,
  // both returning a plain `false` on ANY exception -- a network timeout was
  // indistinguishable from "this account really never finished onboarding",
  // and callers treated `false` as "confirmed orphaned, safe to delete".
  // Tri-state return distinguishes a successful read from a failed one:
  //   true  -- read succeeded, onboarding_completed is true
  //   false -- read succeeded, onboarding_completed is confirmed false
  //   null  -- read failed; status could not be determined -- callers must
  //            NOT treat this as orphaned.
  Future<bool?> checkOnboardingStatus(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('onboarding_completed')
          .eq('id', userId)
          .single();
      return response['onboarding_completed'] == true;
    } catch (e) {
      debugLog('AuthService.checkOnboardingStatus failed: $e');
      return null;
    }
  }
}
