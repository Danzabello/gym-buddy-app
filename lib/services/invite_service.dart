import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

enum InviteRedeemStatus { paired, invalid, rateLimited, offline, malformed }

class InviteRedeemResult {
  final InviteRedeemStatus status;

  /// Set only when [status] is [InviteRedeemStatus.paired].
  final String? inviterId;
  const InviteRedeemResult(this.status, [this.inviterId]);
}

/// [raw] upper-cased, or null unless it is exactly 8 letters and digits.
String? normalizeInviteCode(String raw) {
  final code = raw.trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{8}$').hasMatch(code) ? code : null;
}

/// The code in a Play install referrer. Only the exact form the invite page
/// sends, `invite_code=` and 8 letters and digits, counts; anything else
/// (organic installs, ad campaigns, extra parameters) is ignored.
String? parseInviteReferrer(String? referrer) {
  final m = RegExp(r'^invite_code=([A-Za-z0-9]{8})$').firstMatch(referrer ?? '');
  return m?.group(1)!.toUpperCase();
}

/// Maps one accept_invite call to a result. The RPC answers null for every
/// code it won't accept (unknown, used, expired, own) and raises
/// too_many_attempts past its rate limit; anything that is not an answer
/// from the server means the code could not be checked.
Future<InviteRedeemResult> classifyAccept(Future<Object?> Function() accept) async {
  try {
    final inviterId = await accept();
    return inviterId is String
        ? InviteRedeemResult(InviteRedeemStatus.paired, inviterId)
        : const InviteRedeemResult(InviteRedeemStatus.invalid);
  } on PostgrestException catch (e) {
    if (kDebugMode) debugLog('⚠️ accept_invite: ${e.message}');
    return InviteRedeemResult(e.message.contains('too_many_attempts')
        ? InviteRedeemStatus.rateLimited
        : InviteRedeemStatus.invalid);
  } catch (e) {
    if (kDebugMode) debugLog('⚠️ accept_invite unreachable: $e');
    return const InviteRedeemResult(InviteRedeemStatus.offline);
  }
}

/// Runs [create] once and retries it up to three times. False when every
/// attempt failed.
Future<bool> createTeamWithRetry(
  Future<void> Function() create, {
  Duration delay = const Duration(milliseconds: 800),
}) async {
  for (var attempt = 0;; attempt++) {
    try {
      await create();
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('⚠️ create_invite_team attempt ${attempt + 1}: $e');
      if (attempt == 3) return false;
      await Future.delayed(delay);
    }
  }
}

class InviteService {
  // A getter, so the SharedPreferences parts work without a Supabase client.
  SupabaseClient get _supabase => Supabase.instance.client;

  static const _pendingInviteKey = 'pending_invite_code';
  static const _referrerCheckedKey = 'install_referrer_checked';

  /// "inviteeId:inviterId" of an accepted invite whose team is not made yet.
  static const _pendingTeamKey = 'pending_invite_team';

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

  // ─── Redeem a code: accept it, then make the team ──────────────────────────
  /// The caller's user_profiles row must exist first: accept_invite writes
  /// invites.accepted_by and create_invite_team writes team_members and
  /// friendships, all foreign keys to it.
  /// [rpc] and [userId] are for tests.
  Future<InviteRedeemResult> redeem(
    String raw, {
    Duration retryDelay = const Duration(milliseconds: 800),
    Future<Object?> Function(String fn, Map<String, dynamic> params)? rpc,
    String? userId,
  }) async {
    final code = normalizeInviteCode(raw);
    if (code == null) return const InviteRedeemResult(InviteRedeemStatus.malformed);
    final call = rpc ?? (fn, params) => _supabase.rpc(fn, params: params);

    final result =
        await classifyAccept(() => call('accept_invite', {'p_code': code}));

    if (result.status == InviteRedeemStatus.paired) {
      // Accepted now, so it can't be redeemed again: drop any stored copy.
      await clearPendingInviteCode();
      final me = userId ?? _supabase.auth.currentUser!.id;
      final made = await createTeamWithRetry(
          () => call('create_invite_team', {
                'p_inviter_id': result.inviterId!,
                'p_invitee_id': me,
              }),
          delay: retryDelay);
      if (!made) await rememberTeamRetry(me, result.inviterId!);
    } else if (result.status == InviteRedeemStatus.invalid &&
        await pendingInviteCode() == code) {
      // It will never work: don't offer it again.
      await clearPendingInviteCode();
    }
    return result;
  }

  Future<void> _createTeam(String inviterId, String inviteeId) =>
      _supabase.rpc('create_invite_team', params: {
        'p_inviter_id': inviterId,
        'p_invitee_id': inviteeId,
      });

  /// display_name is a public column. The name never comes from a link or a
  /// referrer, which anyone can write.
  Future<String> inviterName(String inviterId) async {
    try {
      final row = await _supabase
          .from('user_profiles')
          .select('display_name')
          .eq('id', inviterId)
          .maybeSingle();
      final name = (row?['display_name'] as String?)?.trim();
      return name == null || name.isEmpty ? 'your buddy' : name;
    } catch (_) {
      return 'your buddy';
    }
  }

  // ─── Team creation that failed after an accept ─────────────────────────────
  Future<void> rememberTeamRetry(String inviteeId, String inviterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingTeamKey, '$inviteeId:$inviterId');
  }

  /// One silent create_invite_team retry at launch, for the user who
  /// accepted. create_invite_team returns the existing team when there is one.
  Future<void> retryPendingTeam(
    String userId, {
    Future<void> Function(String inviterId)? create,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final parts = prefs.getString(_pendingTeamKey)?.split(':');
    if (parts == null || parts.length != 2 || parts[0] != userId) return;
    await prefs.remove(_pendingTeamKey);
    try {
      await (create ?? (inviterId) => _createTeam(inviterId, userId))(parts[1]);
    } catch (e) {
      if (kDebugMode) debugLog('⚠️ create_invite_team launch retry: $e');
    }
  }

  // ─── The code waiting for the buddy step ───────────────────────────────────
  /// From a link: the newest link wins.
  Future<void> storePendingInviteCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInviteKey, code.toUpperCase());
    if (kDebugMode) debugLog('💾 Stored pending invite code: $code');
  }

  Future<String?> pendingInviteCode() async =>
      (await SharedPreferences.getInstance()).getString(_pendingInviteKey);

  Future<void> clearPendingInviteCode() async =>
      (await SharedPreferences.getInstance()).remove(_pendingInviteKey);

  /// A finished account never reaches the buddy step, so a code stored for
  /// it would only wait for the next account on this phone.
  Future<void> discardPendingIfOnboarded(bool? onboarded) async {
    if (onboarded == true) await clearPendingInviteCode();
  }

  /// Reads the Play install referrer once per install. The flag is set
  /// before the read, so a failed read is not retried either.
  Future<void> readInstallReferrerOnce(Future<String?> Function() read) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_referrerCheckedKey) == true) return;
    await prefs.setBool(_referrerCheckedKey, true);
    try {
      final code = parseInviteReferrer(await read());
      // A link that already brought a code wins over the referrer.
      if (code != null && prefs.getString(_pendingInviteKey) == null) {
        await storePendingInviteCode(code);
      }
    } catch (e) {
      // Sideloaded builds and phones without Play have no referrer.
      if (kDebugMode) debugLog('⚠️ Install referrer: $e');
    }
  }

  static Future<String?> playReferrer() async =>
      (await PlayInstallReferrer.installReferrer
              .timeout(const Duration(seconds: 10)))
          .installReferrer;

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

  // ─── Links and sign-out, for the whole app run ─────────────────────────────
  static final _links = AppLinks();
  static StreamSubscription<Uri>? _linkSub;

  /// Started once from main(), so it outlives every route. It only stores a
  /// code; the buddy step is what redeems it.
  static void startListening() {
    if (_linkSub != null) return;
    _links.getInitialLink().then((uri) {
      if (uri != null) storeCodeFromLink(uri);
    }).catchError((Object e) {
      if (kDebugMode) debugLog('❌ Deep link initial: $e');
    });
    _linkSub = _links.uriLinkStream.listen(storeCodeFromLink, onError: (Object e) {
      if (kDebugMode) debugLog('❌ Deep link stream: $e');
    });
    Supabase.instance.client.auth.onAuthStateChange
        .listen((s) => onAuthEvent(s.event), onError: (_) {});
  }

  static Future<void> storeCodeFromLink(Uri uri) async {
    final code = normalizeInviteCode(uri.queryParameters['code'] ?? '');
    if (code == null) {
      if (kDebugMode) debugLog('⚠️ Ignored a link without a valid invite code');
      return;
    }
    await InviteService().storePendingInviteCode(code);
  }

  /// A code belongs to whoever was about to sign up, not the next account.
  static Future<void> onAuthEvent(AuthChangeEvent event) async {
    if (event == AuthChangeEvent.signedOut) {
      await InviteService().clearPendingInviteCode();
    }
  }
}
