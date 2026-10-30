import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/invite_service.dart';
import '../utils/debug_logger.dart';
import 'onboarding_draft.dart';

/// What an unfinished account already has on the server, read when the app
/// opens so the flow can pick up where it stopped.
class OnboardingResume {
  final String name;
  final int? age;
  final String username;
  final String avatarId;

  /// The inviter's display name when this user already joined through an
  /// invite (read from the server, never from a link).
  final String? pairedWith;

  const OnboardingResume({
    required this.name,
    required this.age,
    required this.username,
    required this.avatarId,
    this.pairedWith,
  });

  /// True when the row holds everything step 5 needs. A row missing any of it
  /// (an older, partial one) restarts at the avatar step, prefilled with what
  /// there is, rather than landing on a buddy step that cannot save.
  bool get complete => name.isNotEmpty && age != null && username.isNotEmpty;

  void applyTo(OnboardingDraft draft) {
    draft.name.text = name;
    draft.age.text = age?.toString() ?? '';
    draft.username.text = username;
    draft.avatarId = avatarId;
    draft.pairedWith = pairedWith;
  }
}

/// The two server reads behind [loadOnboardingResume], so tests can hand it
/// fakes. Both throw when the read fails.
class ResumeReads {
  /// The user's own row through get_my_profile (age is not directly
  /// selectable); empty when there is none.
  final Future<List<Map<String, dynamic>>> Function() profile;

  /// The inviter ids of invites this user accepted, newest first. The invites
  /// SELECT policy lets the invitee read their own accepted rows.
  final Future<List<Map<String, dynamic>>> Function() acceptedInvites;
  final Future<String> Function(String inviterId) inviterName;

  const ResumeReads({
    required this.profile,
    required this.acceptedInvites,
    required this.inviterName,
  });

  factory ResumeReads.live(String userId) {
    final client = Supabase.instance.client;
    return ResumeReads(
      profile: () => client
          .rpc('get_my_profile')
          .select('display_name,age,username,avatar_id'),
      acceptedInvites: () => client
          .from('invites')
          .select('inviter_id')
          .eq('accepted_by', userId)
          .eq('status', 'accepted')
          .order('accepted_at', ascending: false)
          .limit(1),
      inviterName: InviteService().inviterName,
    );
  }
}

/// Null when a read failed: the caller treats that like any failed startup
/// read and never routes into onboarding on it.
Future<OnboardingResume?> loadOnboardingResume(ResumeReads reads) async {
  try {
    final rows = await reads.profile();
    if (rows.isEmpty) return null;
    final row = rows.first;
    final invites = await reads.acceptedInvites();
    final inviterId = invites.isEmpty ? null : invites.first['inviter_id'] as String?;
    return OnboardingResume(
      name: (row['display_name'] as String?)?.trim() ?? '',
      age: (row['age'] as num?)?.toInt(),
      username: (row['username'] as String?) ?? '',
      avatarId: (row['avatar_id'] as String?) ?? 'bear',
      pairedWith: inviterId == null ? null : await reads.inviterName(inviterId),
    );
  } catch (e) {
    debugLog('Onboarding resume read failed: $e');
    return null;
  }
}
