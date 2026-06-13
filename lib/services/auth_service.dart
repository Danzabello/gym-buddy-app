import 'package:supabase_flutter/supabase_flutter.dart';
import 'nickname_service.dart';
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
}
