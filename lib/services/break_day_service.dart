import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';

class BreakDayService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Monday of the week containing [date], as the user's LOCAL calendar date.
  ///
  /// Local frame (per-user tz rework): break_date / check_in_date keys are
  /// the user's own local dates, so the weekly break-cap window is the user's
  /// local Monday–Sunday too — one frame end-to-end, no UTC holdout.
  DateTime getWeekStart(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final daysFromMonday = (dateOnly.weekday - DateTime.monday) % 7;
    return dateOnly.subtract(Duration(days: daysFromMonday));
  }

  /// Set the weekly break day plan (called on Monday or during onboarding)
  Future<void> setWeeklyBreakPlan(int maxBreakDays) async {
    final userId = _supabase.auth.currentUser!.id;
    final weekStart = getWeekStart(DateTime.now());
    
    debugLog('🗓️ Setting weekly break plan: $maxBreakDays break days for week starting ${weekStart.toIso8601String()}');

    // ✅ Write to weekly_break_plans table
    await _supabase.from('weekly_break_plans').upsert({
      'user_id': userId,
      'week_start_date': weekStart.toIso8601String().split('T')[0],
      'max_break_days': maxBreakDays,
    });

    // ✅ ALSO write to user_profiles (for the dialog to read)
    await _supabase.from('user_profiles').update({
      'current_weekly_goal': maxBreakDays,
    }).eq('id', userId);

    debugLog('✅ Weekly break plan set successfully');
  }

  /// Get the current week's break plan
  Future<Map<String, dynamic>?> getCurrentWeekPlan() async {
    final userId = _supabase.auth.currentUser!.id;
    final weekStart = getWeekStart(DateTime.now());

    final response = await _supabase
        .from('weekly_break_plans')
        .select()
        .eq('user_id', userId)
        .eq('week_start_date', weekStart.toIso8601String().split('T')[0])
        .maybeSingle();

    return response;
  }

  /// Get remaining break days for current week
  Future<int> getRemainingBreakDays() async {
    final userId = _supabase.auth.currentUser!.id;
    final weekStart = getWeekStart(DateTime.now());
    final weekEnd = weekStart.add(const Duration(days: 6));

    // Get the plan for this week
    final plan = await getCurrentWeekPlan();
    if (plan == null) {
      debugLog('⚠️ No break plan found for current week');
      return 0;
    }

    final maxBreakDays = plan['max_break_days'] as int;

    // Count how many break days have been used this week (and not cancelled)
    final usedBreakDays = await _supabase
        .from('break_day_usage')
        .select()
        .eq('user_id', userId)
        .gte('break_date', weekStart.toIso8601String().split('T')[0])
        .lte('break_date', weekEnd.toIso8601String().split('T')[0])
        .isFilter('cancelled_at', null)
        .count();

    final remaining = maxBreakDays - (usedBreakDays.count);
    debugLog('📊 Break days: $remaining remaining (${usedBreakDays.count} used / $maxBreakDays max)');
    
    return remaining;
  }

  /// Declare a break day for today — server-authoritative.
  /// The weekly cap, the "today" date (user's own tz frame), and the
  /// reactivation rules are all enforced inside the declare_break_day RPC;
  /// direct inserts into break_day_usage are closed by RLS.
  Future<bool> declareBreakDay() async {
    try {
      final result = await _supabase.rpc('declare_break_day');
      final success = result is Map && result['success'] == true;
      if (success) {
        debugLog('✅ Break day declared (${result['used']}/${result['max']} this week)');
      } else {
        debugLog('❌ Break day rejected: ${result is Map ? result['reason'] : result}');
      }
      return success;
    } catch (e) {
      debugLog('❌ Error declaring break day: $e');
      return false;
    }
  }

  /// Cancel a break day (user decided to work out after all)
  Future<bool> cancelBreakDay() async {
    final userId = _supabase.auth.currentUser!.id;
    // The user's own local date key — must match the break_date written by declareBreakDay.
    final todayStr = localTodayString();

    debugLog('🔄 Cancelling break day for $todayStr');

    final result = await _supabase
        .from('break_day_usage')
        .update({'cancelled_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .eq('break_date', todayStr)
        .isFilter('cancelled_at', null);

    debugLog('✅ Break day cancelled successfully');
    return true;
  }

  /// Check if user is on a break today
  Future<bool> isOnBreakToday(String userId) async {
    // The user's own local date key — matches safe_user_tz() server-side.
    final todayStr = localTodayString();

    final breakDay = await _supabase
        .from('break_day_usage')
        .select()
        .eq('user_id', userId)
        .eq('break_date', todayStr)
        .isFilter('cancelled_at', null)
        .maybeSingle();

    return breakDay != null;
  }

  /// Check if current user is on a break today
  Future<bool> isCurrentUserOnBreakToday() async {
    final userId = _supabase.auth.currentUser!.id;
    return await isOnBreakToday(userId);
  }

  /// Check if user needs to set their weekly plan (it's Monday and no plan exists)
  Future<bool> needsToSetWeeklyPlan() async {
    final today = DateTime.now();
    
    // Only prompt on Monday, or if no plan exists for current week
    final plan = await getCurrentWeekPlan();
    
    return plan == null;
  }

  /// Get break day status for all team members on a specific date
  Future<Map<String, bool>> getTeamBreakDayStatus(List<String> userIds, String date) async {
    final breakDays = await _supabase
        .from('break_day_usage')
        .select('user_id')
        .inFilter('user_id', userIds)
        .eq('break_date', date)
        .isFilter('cancelled_at', null);

    final Map<String, bool> status = {};
    for (var userId in userIds) {
      status[userId] = breakDays.any((bd) => bd['user_id'] == userId);
    }
    
    return status;
  }
}