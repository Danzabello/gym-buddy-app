import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<WorkoutTemplate>> getWorkoutTemplates() async {
    try {
      if (kDebugMode) print('📋 Fetching workout templates...');

      final response = await _supabase
          .from('workout_templates')
          .select()
          .order('category')
          .order('name');

      final templates = (response as List)
          .map((json) => WorkoutTemplate.fromJson(json))
          .toList();

      if (kDebugMode) print('✅ Found ${templates.length} templates');
      return templates;
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching templates: $e');
      return [];
    }
  }

  /// Get templates by category
  Future<List<WorkoutTemplate>> getTemplatesByCategory(String category) async {
    try {
      final response = await _supabase
          .from('workout_templates')
          .select()
          .eq('category', category)
          .order('name');

      return (response as List)
          .map((json) => WorkoutTemplate.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching templates by category: $e');
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
        if (kDebugMode) print('❌ No user logged in');
        return false;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (kDebugMode) print('📝 Logging workout: $workoutName');

      await _supabase.from('workout_logs').insert({
        'user_id': userId,
        'workout_date': today.toIso8601String().split('T')[0],
        'workout_time': now.toUtc().toIso8601String(),
        'template_id': templateId,
        'workout_name': workoutName,
        'workout_category': workoutCategory,
        'workout_emoji': workoutEmoji,
        'actual_duration_minutes': actualDurationMinutes,
        'buddy_id': buddyId,
        'team_id': teamId,
        'notes': notes,
        'intensity_rating': intensityRating,
      });

      if (kDebugMode) print('✅ Workout logged successfully');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error logging workout: $e');
      return false;
    }
  }

  // ============================================
  // GET WORKOUT HISTORY
  // ============================================

  /// Get all workout logs for the current user
  Future<List<WorkoutLog>> getWorkoutHistory({
    int limit = 100,
    DateTime? startDate,
    DateTime? endDate,
    }) async {
    try {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) return [];

        if (kDebugMode) print('📊 Fetching workout history...');

        // ✅ Fetch all workouts, we'll filter in Dart
        final response = await _supabase
            .from('workout_logs')
            .select('''
            *,
            buddy:user_profiles!workout_logs_buddy_id_fkey(display_name)
            ''')
            .eq('user_id', userId)
            .order('workout_date', ascending: false)
            .order('workout_time', ascending: false);

        final allLogs = (response as List).map((json) {
        final buddyData = json['buddy'];
        return WorkoutLog.fromJson({
            ...json,
            'buddy_name': buddyData?['display_name'],
        });
        }).toList();

        // ✅ Filter by date range in Dart
        var filteredLogs = allLogs;
        
        if (startDate != null) {
        final startDateTime = DateTime(startDate.year, startDate.month, startDate.day);
        filteredLogs = filteredLogs.where((log) {
            final logDate = DateTime(log.workoutDate.year, log.workoutDate.month, log.workoutDate.day);
            return logDate.isAfter(startDateTime) || logDate.isAtSameMomentAs(startDateTime);
        }).toList();
        }
        
        if (endDate != null) {
        final endDateTime = DateTime(endDate.year, endDate.month, endDate.day);
        filteredLogs = filteredLogs.where((log) {
            final logDate = DateTime(log.workoutDate.year, log.workoutDate.month, log.workoutDate.day);
            return logDate.isBefore(endDateTime) || logDate.isAtSameMomentAs(endDateTime);
        }).toList();
        }

        // Apply limit
        final limitedLogs = filteredLogs.take(limit).toList();

        if (kDebugMode) print('✅ Found ${limitedLogs.length} workout logs');
        return limitedLogs;
    } catch (e) {
        if (kDebugMode) print('❌ Error fetching workout history: $e');
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

  // ============================================
  // STATISTICS
  // ============================================

  /// Get workout statistics for a date range
  Future<Map<String, dynamic>> getWorkoutStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final workouts = await getWorkoutHistory(
      startDate: startDate,
      endDate: endDate,
      limit: 1000,
    );

    if (workouts.isEmpty) {
      return {
        'total_workouts': 0,
        'total_minutes': 0,
        'avg_duration': 0,
        'favorite_category': null,
        'favorite_workout': null,
      };
    }

    final totalMinutes = workouts
        .map((w) => w.actualDurationMinutes ?? 0)
        .reduce((a, b) => a + b);

    final categoryCount = <String, int>{};
    final workoutCount = <String, int>{};

    for (var workout in workouts) {
      categoryCount[workout.workoutCategory] = 
          (categoryCount[workout.workoutCategory] ?? 0) + 1;
      workoutCount[workout.workoutName] = 
          (workoutCount[workout.workoutName] ?? 0) + 1;
    }

    final favoriteCategory = categoryCount.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    final favoriteWorkout = workoutCount.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    return {
      'total_workouts': workouts.length,
      'total_minutes': totalMinutes,
      'avg_duration': (totalMinutes / workouts.length).round(),
      'favorite_category': favoriteCategory,
      'favorite_workout': favoriteWorkout,
      'category_breakdown': categoryCount,
      'workout_breakdown': workoutCount,
    };
  }
}