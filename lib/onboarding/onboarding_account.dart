import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/coach_max_service.dart';
import '../services/notification_service.dart';
import '../utils/timezone_sync.dart';
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
    case OnboardingState.incomplete:
      // Signed up before and never finished. A row with onboarding_completed
      // false is one a Join on the buddy step wrote, possibly already paired,
      // so it is resumed, never deleted.
      return null;
    case OnboardingState.complete:
      await auth.signOut();
      return kSignupFailedMessage;
    case OnboardingState.unknown:
      // The read failed: nothing is deleted.
      await auth.signOut();
      return kSignupErrorMessage;
  }
}

/// The user_profiles row step 5 writes. Goals, gender and buddy preferences
/// are no longer asked: the columns keep the values the removed steps used to
/// default to.
Map<String, dynamic> onboardingProfileRow(
  OnboardingDraft draft,
  String userId, {
  required bool completed,
}) =>
    {
      'id': userId,
      'display_name': draft.name.text.trim(),
      'username': draft.username.text.toLowerCase(),
      'age': int.parse(draft.age.text.trim()),
      'avatar_id': draft.avatarId,
      'avatar_border': 'simple',
      'fitness_level': 'beginner',
      'looking_for_buddy': true,
      'preferred_workout_style': 'both',
      'onboarding_completed': completed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

/// Writes the user's own row: inserted the first time, updated after that (a
/// Join on step 5 writes it early, then the main button writes it again), so
/// it never fails on a duplicate key. Throws when the write fails.
Future<void> writeOnboardingProfileRow(
  OnboardingDraft draft, {
  required bool completed,
}) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) throw Exception('Authentication failed');
  await upsertProfileRow(
      client, onboardingProfileRow(draft, user.id, completed: completed));
}

/// One INSERT ... ON CONFLICT (id) DO UPDATE. A username taken by someone
/// else still fails, on its own unique key.
Future<void> upsertProfileRow(SupabaseClient client, Map<String, dynamic> row) =>
    client.from('user_profiles').upsert(row, onConflict: 'id');

/// Step 5's main button: the row with onboarding_completed true, then Coach
/// Max and the rest of account setup. Throws when the profile write fails;
/// the caller shows the error and stays on step 5. Invite codes are redeemed
/// by the buddy step itself, before this runs.
Future<void> saveOnboardingProfile(OnboardingDraft draft) async {
  final user = Supabase.instance.client.auth.currentUser;
  await writeOnboardingProfileRow(draft, completed: true);

  await syncDeviceTimezone();

  // Sign-up is the one entry point that never ran initialize() at launch, so
  // without this a new account had no device token until the next cold start.
  await NotificationService().initialize();

  await CoachMaxService().initializeCoachMaxForUser(user!.id);
}
