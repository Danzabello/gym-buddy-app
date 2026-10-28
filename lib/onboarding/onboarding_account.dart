import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/coach_max_service.dart';
import '../services/friend_service.dart';
import '../services/invite_service.dart';
import '../services/notification_service.dart';
import '../utils/debug_logger.dart';
import '../utils/timezone_sync.dart';
import 'onboarding_basic_info_new.dart'
    show discoveryFieldsOf, isOwnProfileDuplicate;
import 'onboarding_draft.dart';

const kSignupFailedMessage =
    'We could not complete your signup. Please check your details and try again, or sign in if you already have an account.';
const kSignupErrorMessage =
    'Something went wrong creating your account. Please try again.';

/// The auth calls step 1 needs, so the decision logic below can be tested
/// without a Supabase client.
abstract class OnboardingAuthPort {
  Future<String?> signUp(String email, String password);
  Future<String?> signIn(String email, String password);
  bool get hasSession;
  Future<OnboardingState> profileState();
  Future<void> signOut();

  /// Removes the push token, deletes the account and signs out.
  Future<void> deleteAccount();
}

class _SupabasePort implements OnboardingAuthPort {
  final _auth = AuthService();
  final _client = Supabase.instance.client;

  @override
  Future<String?> signUp(String email, String password) =>
      _auth.signUp(email: email, password: password);

  @override
  Future<String?> signIn(String email, String password) =>
      _auth.signIn(email: email, password: password);

  @override
  bool get hasSession => _client.auth.currentUser != null;

  @override
  Future<OnboardingState> profileState() =>
      _auth.onboardingState(_client.auth.currentUser!.id);

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    // Token first: the delete-account failure below is swallowed, and in that
    // path the auth user survives with its token row intact.
    await NotificationService().removeToken();
    try {
      await _client.functions.invoke('delete-account');
    } catch (_) {}
    await _client.auth.signOut();
  }
}

/// Step 1: creates the auth user. Returns null on success, else the message
/// to show. A sign-up that fails is retried as a sign-in with the same
/// credentials, so someone who quit part-way can pick up again; a finished
/// account is signed straight back out with the same generic message, so the
/// screen never confirms whether an email is registered.
Future<String?> createOnboardingAuthUser({
  required String email,
  required String password,
  OnboardingAuthPort? port,
}) async {
  final auth = port ?? _SupabasePort();

  final signUpError = await auth.signUp(email, password);
  if (signUpError == null) {
    return auth.hasSession ? null : kSignupFailedMessage;
  }

  // Wrong password for an existing email, or no connection: AuthService
  // swallows the cause, so both get the sign-in hint.
  if (await auth.signIn(email, password) != null) return kSignupFailedMessage;

  switch (await auth.profileState()) {
    case OnboardingState.noProfile:
      return null; // signed up before, never reached the profile step
    case OnboardingState.complete:
      await auth.signOut();
      return kSignupFailedMessage;
    case OnboardingState.incomplete:
      // Half-made profile from an older build: delete it and start clean.
      await auth.deleteAccount();
      final retry = await auth.signUp(email, password);
      return retry == null && auth.hasSession ? null : kSignupErrorMessage;
    case OnboardingState.unknown:
      // The read failed: nothing is deleted.
      await auth.signOut();
      return kSignupErrorMessage;
  }
}

/// Step 5: writes the whole profile in one insert, then sets up Coach Max and
/// any invites carried over from the intro. Throws when the profile write
/// fails; the caller shows the error and stays on step 5.
Future<void> saveOnboardingProfile(
  OnboardingDraft draft, {
  required List<Map<String, dynamic>> pendingInvites,
  required ScaffoldMessengerState messenger,
  required Color successColor,
  required Color warnColor,
}) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) throw Exception('Authentication failed');

  // Goals, gender and buddy preferences are no longer asked: the columns keep
  // the values the removed steps used to default to.
  final profile = {
    'id': user.id,
    'display_name': draft.name.text.trim(),
    'username': draft.username.text.toLowerCase(),
    'age': int.parse(draft.age.text.trim()),
    'avatar_id': draft.avatarId,
    'avatar_border': 'simple',
    'fitness_level': 'beginner',
    'looking_for_buddy': true,
    'preferred_workout_style': 'both',
    'onboarding_completed': true,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
  try {
    await client.from('user_profiles').insert(profile);
  } catch (e) {
    if (!isOwnProfileDuplicate(e)) rethrow;
    await client
        .from('user_profiles')
        .update(discoveryFieldsOf(profile))
        .eq('id', user.id);
  }

  await syncDeviceTimezone();

  // Sign-up is the one entry point that never ran initialize() at launch, so
  // without this a new account had no device token until the next cold start.
  await NotificationService().initialize();

  await CoachMaxService().initializeCoachMaxForUser(user.id);

  final inviteService = InviteService();
  final pendingCode = await inviteService.consumePendingInviteCode();
  if (pendingCode != null) {
    final inviterId = await inviteService.acceptInvite(pendingCode);
    if (inviterId != null) {
      try {
        await client.rpc('create_invite_team', params: {
          'p_inviter_id': inviterId,
          'p_invitee_id': user.id,
        });
      } catch (e) {
        if (kDebugMode) debugLog('create_invite_team failed: $e');
      }
    }
  }

  if (pendingInvites.isNotEmpty) {
    final friendService = FriendService();
    var sent = 0;
    var failed = 0;
    for (final invite in pendingInvites) {
      final result = await friendService.sendFriendRequest(invite['id']);
      result == FriendRequestResult.sent ? sent++ : failed++;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(failed == 0
          ? '$sent buddy request${sent == 1 ? '' : 's'} sent'
          : "$sent sent, $failed couldn't be sent"),
      backgroundColor: failed == 0 ? successColor : warnColor,
      behavior: SnackBarBehavior.floating,
    ));
  }
}
