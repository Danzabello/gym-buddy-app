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

/// Step 1: creates the auth user. Returns null on success, else the message
/// to show. A sign-up that fails is retried as a sign-in with the same
/// credentials, so someone who quit part-way can pick up again; a finished
/// account is signed straight back out with the same generic message, so the
/// screen never confirms whether an email is registered.
Future<String?> createOnboardingAuthUser({
  required String email,
  required String password,
}) async {
  final auth = AuthService();
  final client = Supabase.instance.client;

  final signUpError = await auth.signUp(email: email, password: password);
  if (signUpError == null) {
    return client.auth.currentUser == null ? kSignupFailedMessage : null;
  }

  if (await auth.signIn(email: email, password: password) != null) {
    return kSignupErrorMessage;
  }
  try {
    final row = await client
        .rpc('get_my_profile')
        .select('onboarding_completed')
        .maybeSingle();
    if (row == null) return null; // signed up before, never reached step 5
    if (row['onboarding_completed'] == true) {
      await client.auth.signOut();
      return kSignupFailedMessage;
    }
    // Half-made profile from an older build: delete it and start clean.
    await NotificationService().removeToken();
    try {
      await client.functions.invoke('delete-account');
    } catch (_) {}
    await client.auth.signOut();
    final retry = await auth.signUp(email: email, password: password);
    return retry == null && client.auth.currentUser != null
        ? null
        : kSignupErrorMessage;
  } catch (e) {
    debugLog('Onboarding sign-up recovery failed: $e');
    await client.auth.signOut();
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
