import 'package:supabase_flutter/supabase_flutter.dart';

/// Profile columns other users may read (LIVE-10 allowlist), as far as the
/// onboarding payload carries them.
const kDiscoveryProfileFields = {
  'display_name', 'username', 'avatar_id', 'avatar_border', 'fitness_level',
  'looking_for_buddy',
};

/// True when the profile insert hit this user's existing row (primary key),
/// not the username unique key.
bool isOwnProfileDuplicate(Object e) =>
    e is PostgrestException &&
    e.code == '23505' &&
    e.message.contains('user_profiles_pkey');

Map<String, dynamic> discoveryFieldsOf(Map<String, dynamic> profile) => {
      for (final k in kDiscoveryProfileFields)
        if (profile.containsKey(k)) k: profile[k],
    };
