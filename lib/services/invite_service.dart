import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      if (kDebugMode) print('❌ InviteService.createInvite: $e');
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

  // ─── Look up an invite by code (used during onboarding) ───────────────────
  Future<Map<String, dynamic>?> getInviteByCode(String code) async {
    try {
      final result = await _supabase
          .from('invites')
          .select('id, code, inviter_id, status, user_profiles!invites_inviter_id_fkey(username, display_name)')
          .eq('code', code.toUpperCase())
          .eq('status', 'pending')
          .maybeSingle();

      return result;
    } catch (e) {
      if (kDebugMode) print('❌ InviteService.getInviteByCode: $e');
      return null;
    }
  }

  // ─── Accept an invite — marks it accepted + returns inviter's user_id ──────
  Future<String?> acceptInvite(String code) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // First fetch the invite so we know the inviter
      final invite = await getInviteByCode(code);
      if (invite == null) {
        if (kDebugMode) print('⚠️ InviteService.acceptInvite: invite not found or already used');
        return null;
      }

      // Don't let someone accept their own invite
      if (invite['inviter_id'] == userId) {
        if (kDebugMode) print('⚠️ InviteService.acceptInvite: user tried to accept own invite');
        return null;
      }

      // Mark as accepted
      await _supabase
          .from('invites')
          .update({
            'status': 'accepted',
            'accepted_by': userId,
            'accepted_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('code', code.toUpperCase())
          .eq('status', 'pending');

      return invite['inviter_id'] as String?;
    } catch (e) {
      if (kDebugMode) print('❌ InviteService.acceptInvite: $e');
      return null;
    }
  }

  // ─── Persist a code received via deep link (before user is logged in) ──────
  Future<void> storePendingInviteCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInviteKey, code.toUpperCase());
    if (kDebugMode) print('💾 Stored pending invite code: $code');
  }

  // ─── Retrieve and clear the stored code ────────────────────────────────────
  Future<String?> consumePendingInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingInviteKey);
    if (code != null) {
      await prefs.remove(_pendingInviteKey);
      if (kDebugMode) print('📬 Consumed pending invite code: $code');
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
      if (kDebugMode) print('❌ InviteService.getSentInvites: $e');
      return [];
    }
  }
}