import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/query_ceilings.dart';

/// Bounded reads of `daily_team_checkins`. Errors are thrown: the pages keep
/// their own fallbacks.
class CheckInHistoryService {
  final SupabaseClient _supabase;
  CheckInHistoryService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  Future<Set<String>> _datesSince(String userId, String sinceDate, int limit) async {
    final rows = await _supabase
        .from('daily_team_checkins')
        .select('check_in_date')
        .eq('user_id', userId)
        .gte('check_in_date', sinceDate)
        .order('check_in_date', ascending: false)
        .limit(limit);
    return {
      for (final r in rows)
        if (r['check_in_date'] != null) r['check_in_date'] as String,
    };
  }

  /// The signed-in user's check-in dates from [sinceDate] on.
  Future<Set<String>> myCheckInDatesSince(String sinceDate) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return {};
    return _datesSince(me, sinceDate, kWeekCheckInsCeiling);
  }

  /// [friendId]'s check-in dates from [sinceDate] on.
  Future<Set<String>> checkInDatesSince(String friendId, String sinceDate) =>
      _datesSince(friendId, sinceDate, kMonthCheckInsCeiling);

  /// The ids in [friendIds] that checked in on [date].
  Future<Set<String>> friendsCheckedInOn(String date, List<String> friendIds) async {
    if (friendIds.isEmpty) return {};
    final rows = await _supabase
        .from('daily_team_checkins')
        .select('user_id')
        .eq('check_in_date', date)
        .inFilter('user_id', friendIds)
        .limit(kFriendsCeiling);
    return {for (final r in rows) r['user_id'] as String};
  }
}
