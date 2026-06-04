import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/workout_service.dart';
import '../data/coach_comments.dart';
import 'user_avatar.dart';

class CompletedWorkoutsSection extends StatefulWidget {
  const CompletedWorkoutsSection({super.key, this.refreshTrigger = 0});
  final int refreshTrigger;

  @override
  State<CompletedWorkoutsSection> createState() =>
      _CompletedWorkoutsSectionState();
}

class _CompletedWorkoutsSectionState extends State<CompletedWorkoutsSection> {
  final WorkoutService _workoutService = WorkoutService();
  List<Map<String, dynamic>> _completedWorkouts = [];
  bool _isExpanded = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CompletedWorkoutsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) _load();
  }

  Future<void> _load() async {
    final workouts = await _workoutService.getCompletedWorkouts(limit: 10);
    if (mounted) {
      setState(() {
        _completedWorkouts = workouts;
        _isLoading = false;
      });
    }
  }

  // ── Colour + icon ─────────────────────────────────────────────
  Color _typeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':      return Colors.red[600]!;
      case 'strength':    return Colors.blue[600]!;
      case 'leg day':
      case 'lower body':  return Colors.orange[600]!;
      case 'upper body':  return Colors.purple[600]!;
      case 'full body':   return Colors.indigo[600]!;
      case 'hiit':        return Colors.deepOrange[600]!;
      case 'yoga':        return Colors.teal[600]!;
      default:            return Colors.green[600]!;
    }
  }

  IconData _typeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':      return Icons.directions_run;
      case 'strength':    return Icons.fitness_center;
      case 'upper body':  return Icons.accessibility_new;
      case 'lower body':
      case 'leg day':     return Icons.directions_walk;
      case 'full body':   return Icons.sports_gymnastics;
      case 'hiit':        return Icons.flash_on;
      case 'yoga':        return Icons.self_improvement;
      default:            return Icons.sports;
    }
  }

  // ── Flavour tag (most prominent) ──────────────────────────────
  ({String label, Color color, Color bg}) _flavour(Map<String, dynamic> w) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = w['user_id'] == uid;
    final partnerBailed = w['buddy_id'] != null &&
        (isCreator ? (w['buddy_cancelled'] ?? false) : (w['creator_cancelled'] ?? false));

    if (partnerBailed) return (
      label: 'buddy bailed',
      color: Colors.amber[400]!,
      bg: Colors.amber.withOpacity(0.12),
    );

    final actual  = w['actual_duration_minutes'] as int?;
    final planned = w['planned_duration_minutes'] as int? ?? 60;
    final isAuto  = (w['notes'] as String? ?? '').contains('Auto-completed');

    if (actual != null && !isAuto && actual < (planned * 0.8).round()) return (
      label: 'cut short −${planned - actual}m',
      color: Colors.red[400]!,
      bg: Colors.red.withOpacity(0.1),
    );

    if (w['buddy_id'] != null) return (
      label: 'co-op finish',
      color: Colors.blue[400]!,
      bg: Colors.blue.withOpacity(0.12),
    );

    return (
      label: 'solo win',
      color: Colors.green[400]!,
      bg: Colors.green.withOpacity(0.1),
    );
  }

  // ── Formatting ────────────────────────────────────────────────
  String _duration(int? m) {
    if (m == null) return '—';
    if (m < 60) return '${m}m';
    final h = m ~/ 60; final r = m % 60;
    return r > 0 ? '${h}h ${r}m' : '${h}h';
  }

  String _date(String? s) {
    if (s == null) return '';
    try {
      final d = DateTime.parse(s);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(d.year, d.month, d.day);
      if (day == today) return 'Today';
      if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
      return '${d.month}/${d.day}';
    } catch (_) { return s; }
  }

  String _time(Map<String, dynamic> w) {
    final ts = w['workout_completed_at'] as String?;
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final h = dt.hour; final m = dt.minute;
      final p = h >= 12 ? 'PM' : 'AM';
      final dh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$dh:${m.toString().padLeft(2, '0')} $p';
    } catch (_) { return ''; }
  }

  String _vsPlanned(Map<String, dynamic> w) {
    final a = w['actual_duration_minutes'] as int?;
    final p = w['planned_duration_minutes'] as int?;
    if (a == null || p == null) return '—';
    if ((w['notes'] as String? ?? '').contains('Auto-completed')) return 'auto';
    final d = a - p;
    if (d > 0) return '+${d}m';
    if (d < 0) return '${d}m';
    return 'exact';
  }

  Color _vsColor(String vs) {
    if (vs.startsWith('+')) return Colors.green[400]!;
    if (vs.startsWith('-')) return Colors.red[400]!;
    if (vs == 'exact') return Colors.blue[400]!;
    return Colors.grey[500]!;
  }

  // ── Partner helpers ───────────────────────────────────────────
  String? _partnerName(Map<String, dynamic> w) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final p = w['user_id'] == uid ? w['buddy'] : w['creator'];
    return p?['display_name'] as String?;
  }

  String? _partnerAvatarId(Map<String, dynamic> w) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final p = w['user_id'] == uid ? w['buddy'] : w['creator'];
    return p?['avatar_id'] as String?;
  }

  // ── Coach Max comment (seeded from workout ID) ────────────────
  String _coachComment(Map<String, dynamic> w) {
    final id = w['id'] as String? ?? '';
    int seed = 0;
    for (final c in id.codeUnits) seed = (seed * 31 + c) & 0x7FFFFFFF;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = w['user_id'] == uid;
    final partnerBailed = w['buddy_id'] != null &&
        (isCreator ? (w['buddy_cancelled'] ?? false) : (w['creator_cancelled'] ?? false));

    final actual  = w['actual_duration_minutes'] as int?;
    final planned = w['planned_duration_minutes'] as int? ?? 60;
    final isAuto  = (w['notes'] as String? ?? '').contains('Auto-completed');
    final type    = (w['workout_type'] as String? ?? '').toLowerCase();
    final partner = _partnerName(w) ?? 'your buddy';

    List<String> pool;

    if (partnerBailed) {
      pool = CoachComments.buddyBailed;
    } else if (w['buddy_id'] != null) {
      if (actual != null && !isAuto && actual < (planned * 0.8).round())
        pool = CoachComments.coopShort;
      else if (actual != null && !isAuto && actual > (planned * 1.1).round())
        pool = CoachComments.coopOver;
      else
        pool = CoachComments.coopCrushed;
    } else {
      if (actual != null && !isAuto && actual < (planned * 0.8).round()) {
        pool = CoachComments.soloShort;
      } else if (actual != null && !isAuto && actual > (planned * 1.1).round()) {
        pool = CoachComments.soloOver;
      } else {
        // ~30% chance of type-specific or time-specific flavour
        final typePool = type == 'strength' ? CoachComments.strengthSpecific
            : type == 'cardio'   ? CoachComments.cardioSpecific
            : type == 'hiit'     ? CoachComments.hiitSpecific
            : type == 'yoga'     ? CoachComments.yogaSpecific
            : null;

        List<String>? timePool;
        final ts = w['workout_completed_at'] as String?;
        if (ts != null) {
          try {
            final hour = DateTime.parse(ts).toLocal().hour;
            if (hour < 9) timePool = CoachComments.morning;
            else if (hour >= 21) timePool = CoachComments.lateNight;
          } catch (_) {}
        }

        if (typePool != null && seed % 3 == 0)      pool = typePool;
        else if (timePool != null && seed % 3 == 1) pool = timePool;
        else                                         pool = CoachComments.soloCrushed;
      }
    }

    return (pool[seed % pool.length])
        .replaceAll('{partner}', partner)
        .replaceAll('{planned}', '${planned}m')
        .replaceAll('{type}', w['workout_type'] ?? 'workout');
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    final appColors = AppColors.of(context);

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: appColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: appColors.cardBorder, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.history, color: Colors.green[400], size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent workouts',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface)),
                      Text('${_completedWorkouts.length} completed',
                          style: TextStyle(fontSize: 12, color: appColors.subtleText)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, color: appColors.subtleText),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          ..._completedWorkouts.map(_buildCard).toList(),
        ],
      ],
    );
  }

  // ── Compact card ──────────────────────────────────────────────
  Widget _buildCard(Map<String, dynamic> workout) {
    final appColors  = AppColors.of(context);
    final type       = workout['workout_type'] as String? ?? 'Workout';
    final color      = _typeColor(type);
    final f          = _flavour(workout);
    final time       = _time(workout);
    final avatarId   = _partnerAvatarId(workout);
    final partnerName = _partnerName(workout);
    final hasBuddy   = partnerName != null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showDetail(workout);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: appColors.cardBackground,
              border: Border(
                left: BorderSide(color: color, width: 3),
                top: BorderSide(color: appColors.cardBorder, width: 0.5),
                right: BorderSide(color: appColors.cardBorder, width: 0.5),
                bottom: BorderSide(color: appColors.cardBorder, width: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              child: Row(
                children: [
                  // Workout icon
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_typeIcon(type), color: color, size: 20),
                  ),
                  const SizedBox(width: 10),

                  // Main info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface)),
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.timer_outlined, size: 11, color: appColors.subtleText),
                          const SizedBox(width: 3),
                          Text(_duration(workout['actual_duration_minutes'] as int?),
                              style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                          _pipe(appColors),
                          Icon(Icons.calendar_today_outlined, size: 11, color: appColors.subtleText),
                          const SizedBox(width: 3),
                          Text(_date(workout['workout_date'] as String?),
                              style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                          if (time.isNotEmpty) ...[
                            _pipe(appColors),
                            Text(time, style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: f.bg, borderRadius: BorderRadius.circular(6)),
                              child: Text(f.label,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                      color: f.color)),
                            ),
                            if (hasBuddy) ...[
                              const SizedBox(width: 7),
                              // Partner avatar — small inline
                              if (avatarId != null)
                                UserAvatar(avatarId: avatarId, size: 16)
                              else
                                CircleAvatar(
                                  radius: 8,
                                  backgroundColor: Colors.blue.withOpacity(0.2),
                                  child: Text(
                                    partnerName!.substring(0, 1).toUpperCase(),
                                    style: TextStyle(fontSize: 9, color: Colors.blue[400]),
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Text(partnerName!,
                                  style: TextStyle(fontSize: 10, color: Colors.blue[400])),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  Icon(Icons.chevron_right, size: 16,
                      color: appColors.subtleText.withOpacity(0.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pipe(AppColors c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Container(width: 1, height: 9, color: c.cardBorder),
      );

  // ── Detail bottom sheet ───────────────────────────────────────
  void _showDetail(Map<String, dynamic> workout) {
    final vs = _vsPlanned(workout);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
        workout: workout,
        typeColor: _typeColor(workout['workout_type']),
        typeIcon: _typeIcon(workout['workout_type']),
        flavour: _flavour(workout),
        duration: _duration(workout['actual_duration_minutes'] as int?),
        date: _date(workout['workout_date'] as String?),
        time: _time(workout),
        vsPlanned: vs,
        vsColor: _vsColor(vs),
        partnerName: _partnerName(workout),
        partnerAvatarId: _partnerAvatarId(workout),
        coachComment: _coachComment(workout),
        plannedDuration: workout['planned_duration_minutes'] as int? ?? 60,
        actualDuration: workout['actual_duration_minutes'] as int?,
        isAuto: (workout['notes'] as String? ?? '').contains('Auto-completed'),
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────
class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> workout;
  final Color typeColor;
  final IconData typeIcon;
  final ({String label, Color color, Color bg}) flavour;
  final String duration, date, time, vsPlanned;
  final Color vsColor;
  final String? partnerName, partnerAvatarId, coachComment;
  final int plannedDuration;
  final int? actualDuration;
  final bool isAuto;

  const _DetailSheet({
    required this.workout, required this.typeColor, required this.typeIcon,
    required this.flavour, required this.duration, required this.date,
    required this.time, required this.vsPlanned, required this.vsColor,
    required this.partnerName, required this.partnerAvatarId,
    required this.coachComment, required this.plannedDuration,
    required this.actualDuration, required this.isAuto,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final progress = (actualDuration != null && !isAuto)
        ? (actualDuration! / plannedDuration).clamp(0.0, 1.0)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: appColors.divider, borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workout['workout_type'] ?? 'Workout',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: flavour.bg, borderRadius: BorderRadius.circular(6)),
                          child: Text(flavour.label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: flavour.color)),
                        ),
                        const SizedBox(width: 8),
                        Text('$date${time.isNotEmpty ? ' · $time' : ''}',
                            style: TextStyle(fontSize: 12, color: appColors.subtleText)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: appColors.divider),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _pill(context, appColors, duration, 'actual',
                    Theme.of(context).colorScheme.onSurface),
                const SizedBox(width: 10),
                _pill(context, appColors, vsPlanned, 'vs plan', vsColor),
                const SizedBox(width: 10),
                _pill(context, appColors, '${plannedDuration}m', 'planned',
                    appColors.subtleText),
              ],
            ),
          ),

          // Duration bar
          if (progress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('duration vs plan',
                      style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: appColors.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0 ? Colors.green[400]! : Colors.orange[400]!),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0', style: TextStyle(fontSize: 10, color: appColors.subtleText)),
                      Text('${plannedDuration}m goal',
                          style: TextStyle(fontSize: 10, color: appColors.subtleText)),
                    ],
                  ),
                ],
              ),
            ),

          // Partner row
          if (partnerName != null) ...[
            Divider(height: 1, color: appColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (partnerAvatarId != null)
                    UserAvatar(avatarId: partnerAvatarId!, size: 36)
                  else
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.blue.withOpacity(0.15),
                      child: Text(
                        partnerName!.substring(0, 1).toUpperCase(),
                        style: TextStyle(fontSize: 14, color: Colors.blue[400]),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(partnerName!,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                              color: Colors.blue[400])),
                      Text('workout partner · streak protected',
                          style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Coach Max
          if (coachComment != null && coachComment!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: appColors.sectionBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: appColors.cardBorder, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('🤖', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('COACH MAX',
                          style: TextStyle(fontSize: 10, letterSpacing: 0.8,
                              fontWeight: FontWeight.w600, color: appColors.subtleText)),
                    ]),
                    const SizedBox(height: 8),
                    Text(coachComment!,
                        style: TextStyle(fontSize: 13, height: 1.55,
                            color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, AppColors appColors,
      String val, String label, Color valColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: valColor)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: appColors.subtleText)),
          ],
        ),
      ),
    );
  }
}