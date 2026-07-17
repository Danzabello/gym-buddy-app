import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

class InviteService {
  final _supabase = Supabase.instance.client;

  static const _pendingInviteKey = 'pending_invite_code';

  // ─── Generate a new invite code for the current user ───────────────────────
  Future<String?> createInvite() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final code = await _supabase.rpc(
        'create_invite',
        params: {'p_inviter_id': userId},
      );

      return code as String?;
    } catch (e) {
      if (kDebugMode) debugLog('❌ InviteService.createInvite: $e');
      return null;
    }
  }

  // ─── Build the shareable link from a code ──────────────────────────────────
  String buildInviteLink(String code) {
    // Once Firebase Hosting is set up this becomes the App Link domain.
    // For now we use the Supabase Edge Function redirect URL.
    return 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/invite-redirect?code=$code';
  }

  // ─── Create invite + return the full shareable link ────────────────────────
  Future<String?> createInviteLink() async {
    final code = await createInvite();
    if (code == null) return null;
    return buildInviteLink(code);
  }

  // ─── Accept an invite — marks it accepted + returns inviter's user_id ──────
  Future<String?> acceptInvite(String code) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Server-side accept: the accept_invite RPC looks up by code, validates
      // state, and marks accepted atomically inside a SECURITY DEFINER function.
      // The client no longer has direct UPDATE on invites (Group C / LIVE-12).
      final inviterId = await _supabase.rpc(
        'accept_invite',
        params: {'p_code': code.toUpperCase()},
      );

      return inviterId as String?;
    } catch (e) {
      // Named RPC failures (invite_not_found / invite_already_accepted /
      // invite_expired / cannot_accept_own_invite / unauthenticated) all land
      // here and, as before, resolve to a null return -> onboarding skips pairing.
      if (kDebugMode) debugLog('⚠️ InviteService.acceptInvite: $e');
      return null;
    }
  }

  // ─── Persist a code received via deep link (before user is logged in) ──────
  Future<void> storePendingInviteCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInviteKey, code.toUpperCase());
    if (kDebugMode) debugLog('💾 Stored pending invite code: $code');
  }

  // ─── Retrieve and clear the stored code ────────────────────────────────────
  Future<String?> consumePendingInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingInviteKey);
    if (code != null) {
      await prefs.remove(_pendingInviteKey);
      if (kDebugMode) debugLog('📬 Consumed pending invite code: $code');
    }
    return code;
  }

  // ─── Fetch all invites sent by the current user ────────────────────────────
  Future<List<Map<String, dynamic>>> getSentInvites() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final result = await _supabase
          .from('invites')
          .select('*')
          .eq('inviter_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      if (kDebugMode) debugLog('❌ InviteService.getSentInvites: $e');
      return [];
    }
  }
}