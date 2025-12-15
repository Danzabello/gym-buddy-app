import 'package:supabase_flutter/supabase_flutter.dart';

class BreakDayService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get the start of the current week (Monday)
  DateTime getWeekStart(DateTime date) {
    final daysFromMonday = (date.weekday - DateTime.monday) % 7;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysFromMonday));
  }

  /// Set the weekly break day plan (called on Monday or during onboarding)
  Future<void> setWeeklyBreakPlan(int maxBreakDays) async {
    final userId = _supabase.auth.currentUser!.id;
    final weekStart = getWeekStart(DateTime.now());
    
    print('🗓️ Setting weekly break plan: $maxBreakDays break days for week starting ${weekStart.toIso8601String()}');

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

    print('✅ Weekly break plan set successfully');
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
      print('⚠️ No break plan found for current week');
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
    print('📊 Break days: $remaining remaining (${usedBreakDays.count} used / $maxBreakDays max)');
    
    return remaining;
  }

  /// Declare a break day for today
  Future<bool> declareBreakDay() async {
    final userId = _supabase.auth.currentUser!.id;
    final today = DateTime.now();
    final todayStr = DateTime(today.year, today.month, today.day).toIso8601String().split('T')[0];

    // Check if user has break days remaining
    final remaining = await getRemainingBreakDays();
    if (remaining <= 0) {
      print('❌ No break days remaining for this week');
      return false;
    }

    // Check if already declared for today
    final existing = await _supabase
        .from('break_day_usage')
        .select()
        .eq('user_id', userId)
        .eq('break_date', todayStr)
        .maybeSingle();

    if (existing != null && existing['cancelled_at'] == null) {
      print('⚠️ Break day already declared for today');
      return false;
    }

    print('🛌 Declaring break day for $todayStr');

    await _supabase.from('break_day_usage').upsert({
      'user_id': userId,
      'break_date': todayStr,
      'declared_at': DateTime.now().toIso8601String(),
      'cancelled_at': null,
    });

    print('✅ Break day declared successfully');
    return true;
  }

  /// Cancel a break day (user decided to work out after all)
  Future<bool> cancelBreakDay() async {
    final userId = _supabase.auth.currentUser!.id;
    final today = DateTime.now();
    final todayStr = DateTime(today.year, today.month, today.day).toIso8601String().split('T')[0];

    print('🔄 Cancelling break day for $todayStr');

    final result = await _supabase
        .from('break_day_usage')
        .update({'cancelled_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .eq('break_date', todayStr)
        .isFilter('cancelled_at', null);

    print('✅ Break day cancelled successfully');
    return true;
  }

  /// Check if user is on a break today
  Future<bool> isOnBreakToday(String userId) async {
    final today = DateTime.now();
    final todayStr = DateTime(today.year, today.month, today.day).toIso8601String().split('T')[0];

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