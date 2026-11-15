import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/input_validators.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';


class WorkoutTemplate {
  final String id;
  final String name;
  final String? description;
  final String category;
  final int defaultDurationMinutes;
  final String emoji;
  final bool isSystemTemplate;

  WorkoutTemplate({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    required this.defaultDurationMinutes,
    required this.emoji,
    required this.isSystemTemplate,
  });

  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) {
    return WorkoutTemplate(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      category: json['category'],
      defaultDurationMinutes: json['default_duration_minutes'] ?? 30,
      emoji: json['emoji'] ?? '💪',
      isSystemTemplate: json['is_system_template'] ?? true,
    );
  }
}

class WorkoutLog {
  final String id;
  final String userId;
  final DateTime workoutDate;
  final DateTime workoutTime;
  final String? templateId;
  final String workoutName;
  final String workoutCategory;
  final String workoutEmoji;
  final int? plannedDurationMinutes;
  final int? actualDurationMinutes;
  final String? buddyId;
  final String? buddyName;
  final String? teamId;
  final String? notes;
  final int? intensityRating;

  WorkoutLog({
    required this.id,
    required this.userId,
    required this.workoutDate,
    required this.workoutTime,
    this.templateId,
    required this.workoutName,
    required this.workoutCategory,
    required this.workoutEmoji,
    this.plannedDurationMinutes,
    this.actualDurationMinutes,
    this.buddyId,
    this.buddyName,
    this.teamId,
    this.notes,
    this.intensityRating,
  });

  factory WorkoutLog.fromJson(Map<String, dynamic> json) {
    return WorkoutLog(
      id: json['id'],
      userId: json['user_id'],
      workoutDate: DateTime.parse(json['workout_date']),
      workoutTime: DateTime.parse(json['workout_time']),
      templateId: json['template_id'],
      workoutName: json['workout_name'],
      workoutCategory: json['workout_category'],
      workoutEmoji: json['workout_emoji'] ?? '💪',
      plannedDurationMinutes: json['planned_duration_minutes'],
      actualDurationMinutes: json['actual_duration_minutes'],
      buddyId: json['buddy_id'],
      buddyName: json['buddy_name'],
      teamId: json['team_id'],
      notes: json['notes'],
      intensityRating: json['intensity_rating'],
    );
  }
}

class CalendarDay {
  final DateTime date;
  final List<WorkoutLog> workouts;
  final bool hasWorkout;
  final bool isToday;
  final bool isFuture;

  CalendarDay({
    required this.date,
    required this.workouts,
    required this.isToday,
    required this.isFuture,
  }) : hasWorkout = workouts.isNotEmpty;

  String get dayNumber => date.day.toString();
  
  String get statusEmoji {
    if (workouts.isEmpty) return '';
    if (workouts.length == 1) return workouts.first.workoutEmoji;
    return '${workouts.first.workoutEmoji}+${workouts.length - 1}';
  }
}

class WorkoutHistoryService {
  final SupabaseClient _supabase;
  WorkoutHistoryService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  Future<List<WorkoutTemplate>> getWorkoutTemplates() async {
    try {
      if (kDebugMode) debugLog('📋 Fetching workout templates...');

      final response = await _supabase
          .from('workout_templates')
          .select()
          .order('category')
          .order('name');

      final templates = (response as List)
          .map((json) => WorkoutTemplate.fromJson(json))
          .toList();

      if (kDebugMode) debugLog('✅ Found ${templates.length} templates');
      return templates;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error fetching templates: $e');
      return [];
    }
  }

  // ============================================
  // LOG WORKOUTS
  // ============================================

  /// Create a workout log entry
  Future<bool> logWorkout({
    required String templateId,
    required String workoutName,
    required String workoutCategory,
    required String workoutEmoji,
    required int actualDurationMinutes,
    String? buddyId,
    String? teamId,
    String? notes,
    int? intensityRating,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        if (kDebugMode) debugLog('❌ No user logged in');
        return false;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // 🔒 Service-layer payload guard — truncate before DB insert
      final safeNotes = InputValidators.truncate(notes, InputLimits.notesMax);
      final safeWorkoutName = InputValidators.truncate(workoutName, InputLimits.workoutNameMax)
          ?? workoutName.substring(0, workoutName.length.clamp(0, InputLimits.workoutNameMax));

      if (kDebugMode) debugLog('📝 Logging workout: $safeWorkoutName');

      await _supabase.from('workout_logs').insert({
        'user_id': userId,
        'workout_date': today.toIso8601String().split('T')[0],
        'workout_time': now.toUtc().toIso8601String(),
        'template_id': templateId,
        'workout_name': safeWorkoutName,
        'workout_category': workoutCategory,
        'workout_emoji': workoutEmoji,
        'actual_duration_minutes': actualDurationMinutes,
        'buddy_id': buddyId,
        'team_id': teamId,
        'notes': safeNotes,                         // 🔒 sanitised
        'intensity_rating': intensityRating,
      });

      if (kDebugMode) debugLog('✅ Workout logged successfully');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error logging workout: $e');
      return false;
    }
  }

  // ============================================
  // GET WORKOUT HISTORY
  // ============================================

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The newest [limit] workout logs of the current user, optionally within
  /// a date range (both ends inclusive).
  Future<List<WorkoutLog>> getWorkoutHistory({
    int limit = 100,
    DateTime? startDate,
    DateTime? endDate,
    }) async {
    try {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) return [];

        if (kDebugMode) debugLog('📊 Fetching workout history...');

        // The date range and the limit go to the server, so it returns at
        // most [limit] rows however long the history is. workout_date is a
        // date column, so both ends are inclusive.
        var query = _supabase
            .from('workout_logs')
            .select('''
            *,
            buddy:user_profiles!workout_logs_buddy_id_fkey(display_name)
            ''')
            .eq('user_id', userId);
        if (startDate != null) query = query.gte('workout_date', _dateKey(startDate));
        if (endDate != null) query = query.lte('workout_date', _dateKey(endDate));
        final response = await query
            .order('workout_date', ascending: false)
            .order('workout_time', ascending: false)
            .limit(limit);

        final limitedLogs = (response as List).map((json) {
        final buddyData = json['buddy'];
        return WorkoutLog.fromJson({
            ...json,
            'buddy_name': buddyData?['display_name'],
        });
        }).toList();

        if (kDebugMode) debugLog('✅ Found ${limitedLogs.length} workout logs');
        return limitedLogs;
    } catch (e) {
        if (kDebugMode) debugLog('❌ Error fetching workout history: $e');
        return [];
    }
    }

  /// Get workout logs for a specific month
  Future<List<WorkoutLog>> getWorkoutsForMonth(DateTime month) async {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);

    return getWorkoutHistory(
      startDate: firstDay,
      endDate: lastDay,
      limit: 100,
    );
  }

  /// Get calendar data for a month
  Future<List<CalendarDay>> getCalendarMonth(DateTime month) async {
    final workouts = await getWorkoutsForMonth(month);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Group workouts by date
    final Map<String, List<WorkoutLog>> workoutsByDate = {};
    for (var workout in workouts) {
      final dateKey = workout.workoutDate.toIso8601String().split('T')[0];
      workoutsByDate.putIfAbsent(dateKey, () => []).add(workout);
    }

    // Generate calendar days
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    
    final List<CalendarDay> calendarDays = [];
    
    for (var day = firstDay; day.isBefore(lastDay.add(const Duration(days: 1))); day = day.add(const Duration(days: 1))) {
      final dateKey = day.toIso8601String().split('T')[0];
      final dayWorkouts = workoutsByDate[dateKey] ?? [];
      
      calendarDays.add(CalendarDay(
        date: day,
        workouts: dayWorkouts,
        isToday: day.isAtSameMomentAs(todayDate),
        isFuture: day.isAfter(todayDate),
      ));
    }

    return calendarDays;
  }
}