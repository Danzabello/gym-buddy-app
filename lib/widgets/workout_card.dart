import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';

class WorkoutCard extends StatefulWidget {
  final Map<String, dynamic> workout;
  final String partnerName;
  final bool isCreator;
  final bool isBuddy;
  final String? buddyStatus;
  final String? workoutStatus;
  final VoidCallback? onStart;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onJoin;
  final VoidCallback? onOpenTimer;
  final VoidCallback? onReady;
  final VoidCallback? onCancelReady;
  final VoidCallback? onStartTogether;

  const WorkoutCard({
    super.key,
    required this.workout,
    required this.partnerName,
    required this.isCreator,
    required this.isBuddy,
    this.buddyStatus,
    this.workoutStatus,
    this.onStart,
    this.onComplete,
    this.onCancel,
    this.onAccept,
    this.onDecline,
    this.onJoin,
    this.onOpenTimer,
    this.onReady,
    this.onCancelReady,
    this.onStartTogether,
  });

  @override
  State<WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<WorkoutCard> {
  Timer? _timer;
  int _joinWindowRemaining = 0;
  int _workoutElapsed = 0;

  @override
  void initState() {
    super.initState();
    _initTimers();
  }

  @override
  void didUpdateWidget(WorkoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workout['id'] != widget.workout['id'] ||
        oldWidget.workoutStatus != widget.workoutStatus) {
      _timer?.cancel();
      _initTimers();
    }
  }

  void _initTimers() {
    final startedAt = widget.workout['workout_started_at'];
    final plannedDuration = widget.workout['planned_duration_minutes'] ?? 30;

    if (widget.workoutStatus == 'in_progress') {
      if (startedAt != null) {
        final startTime = DateTime.parse(startedAt);
        final now = DateTime.now();
        _workoutElapsed = now.difference(startTime).inSeconds.clamp(0, 999999);
        final joinWindowMinutes = plannedDuration ~/ 4;
        final joinWindowEnd = startTime.add(Duration(minutes: joinWindowMinutes));
        _joinWindowRemaining = joinWindowEnd.difference(now).inSeconds;
      }
      // Always tick for in_progress — even if startedAt is null, timer counts up
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _workoutElapsed++;
            if (_joinWindowRemaining > 0) _joinWindowRemaining--;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _getCreatorState() {
    final creatorJoined = widget.workout['creator_joined'] ?? false;
    final startedByUserId = widget.workout['started_by_user_id'];
    final buddyId = widget.workout['buddy_id'];

    if (widget.workoutStatus == 'completed') {
      if (!creatorJoined && startedByUserId == buddyId) return 'buddy_completed';
      return 'completed';
    }

    if (widget.workoutStatus == 'in_progress') {
      if (startedByUserId == buddyId && !creatorJoined) {
        return _joinWindowRemaining > 0 ? 'waiting_to_join' : 'window_expired';
      }
      if (creatorJoined || startedByUserId == widget.workout['user_id']) {
        return 'in_progress';
      }
    }

    return 'scheduled';
  }

  // ── Mutual ready check helpers ──────────────────────────────────────────
  bool get _isBuddyWorkout => widget.workout['buddy_id'] != null;

  bool get _readyActive {
    if (widget.workout['creator_ready'] != true) return false;
    final expires = widget.workout['ready_expires_at'];
    if (expires == null) return false;
    try {
      return DateTime.parse(expires).isAfter(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }

  // Creator pressed I'm Ready — waiting for buddy to start
  bool get _creatorWaitingReady =>
      widget.isCreator &&
      widget.workoutStatus == 'scheduled' &&
      widget.buddyStatus == 'accepted' &&
      _readyActive;

  // Buddy sees partner ready — can start together
  bool get _buddyCanStartTogether =>
      widget.isBuddy &&
      widget.workoutStatus == 'scheduled' &&
      widget.buddyStatus == 'accepted' &&
      _readyActive;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final isIncomingInvite = widget.isBuddy && widget.buddyStatus == 'pending';
    final creatorState = widget.isCreator ? _getCreatorState() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _getCardShadowColor(creatorState),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: _getCardBorder(creatorState, isIncomingInvite, appColors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWorkoutIcon(creatorState, appColors),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.workout['workout_type'] ?? 'Workout',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          _buildStatusChip(creatorState, appColors),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.blue[400]),
                          const SizedBox(width: 4),
                          Text(
                            'with ${widget.partnerName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[400],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInfoTags(appColors),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_creatorWaitingReady) _buildWaitingReadySection(appColors),
          if (_buddyCanStartTogether) _buildPartnerReadySection(appColors),
          if (creatorState == 'waiting_to_join') _buildJoinWindowSection(appColors),
          if (creatorState == 'window_expired') _buildWindowExpiredSection(appColors),
          if (creatorState == 'buddy_completed') _buildBuddyCompletedSection(),
          if (creatorState == 'in_progress' ||
              (widget.isBuddy && widget.workoutStatus == 'in_progress'))
            _buildInProgressSection(appColors),
          if (isIncomingInvite) _buildInviteActions(),
          if (!isIncomingInvite) _buildWorkoutActions(creatorState, appColors),
        ],
      ),
    );
  }

  Widget _buildDurationTag(int? minutes, AppColors appColors) {
    final color = _durationColor(minutes);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            _formatDuration(minutes),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _durationColor(int? minutes) {
    if (minutes == null) return AppColors.of(context).subtleText;
    if (minutes <= 20)  return Colors.grey[500]!;
    if (minutes <= 30)  return Colors.blue[600]!;
    if (minutes <= 45)  return Colors.green[600]!;
    if (minutes <= 60)  return Colors.teal[600]!;
    if (minutes <= 75)  return Colors.purple[600]!;
    if (minutes <= 90)  return Colors.deepPurple[600]!;
    return Colors.red[600]!;
  }

  Color _getCardShadowColor(String? state) {
    switch (state) {
      case 'waiting_to_join':
        return Colors.orange.withOpacity(0.25);
      case 'in_progress':
        return Colors.green.withOpacity(0.25);
      case 'window_expired':
        return Colors.black.withOpacity(0.15);
      case 'buddy_completed':
        return Colors.green.withOpacity(0.15);
      default:
        return Colors.black.withOpacity(0.15);
    }
  }

  Border? _getCardBorder(String? state, bool isInvite, AppColors appColors) {
    if (state == 'waiting_to_join') return Border.all(color: Colors.orange.withOpacity(0.5), width: 2);
    if (state == 'in_progress') return Border.all(color: Colors.green.withOpacity(0.4), width: 2);
    if (isInvite) return Border.all(color: Colors.blue.withOpacity(0.4), width: 2);
    return Border.all(color: appColors.cardBorder, width: 0.5);
  }

  Widget _buildWorkoutIcon(String? state, AppColors appColors) {
    final workoutType = widget.workout['workout_type'] ?? 'Workout';
    final color = _getWorkoutColor(workoutType);
    final icon = _getWorkoutIcon(workoutType);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: state == 'window_expired'
            ? appColors.sectionBackground
            : color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon,
        color: state == 'window_expired' ? appColors.subtleText : color,
        size: 28,
      ),
    );
  }

  Widget _buildStatusChip(String? state, AppColors appColors) {
    Color bgColor;
    Color textColor;
    String label;

    switch (state) {
      case 'waiting_to_join':
        bgColor = Colors.orange.withOpacity(0.15);
        textColor = Colors.orange[300]!;
        label = '⏳ Waiting';
        break;
      case 'in_progress':
        bgColor = Colors.green.withOpacity(0.15);
        textColor = Colors.green[400]!;
        label = '🔥 Active';
        break;
      case 'window_expired':
        bgColor = appColors.sectionBackground;
        textColor = appColors.subtleText;
        label = '❌ Missed';
        break;
      case 'buddy_completed':
        bgColor = Colors.green.withOpacity(0.15);
        textColor = Colors.green[400]!;
        label = '✅ Done';
        break;
      default:
        if (_creatorWaitingReady) {
          bgColor = Colors.orange.withOpacity(0.15);
          textColor = Colors.orange[300]!;
          label = '⏳ Waiting';
        } else if (_buddyCanStartTogether) {
          bgColor = Colors.green.withOpacity(0.15);
          textColor = Colors.green[400]!;
          label = '🟢 Partner ready';
        } else if (widget.isBuddy && widget.buddyStatus == 'pending') {
          bgColor = Colors.blue.withOpacity(0.15);
          textColor = Colors.blue[300]!;
          label = '📨 Invite';
        } else if (widget.workoutStatus == 'in_progress') {
          bgColor = Colors.green.withOpacity(0.15);
          textColor = Colors.green[400]!;
          label = '🔥 Active';
        } else {
          bgColor = Colors.blue.withOpacity(0.1);
          textColor = Colors.blue[300]!;
          label = '📅 Scheduled';
        }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  Widget _buildInfoTags(AppColors appColors) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildInfoTag(icon: Icons.calendar_today, text: _formatDate(widget.workout['workout_date']), appColors: appColors),
        _buildInfoTag(icon: Icons.access_time, text: _formatTime(widget.workout['workout_time']), appColors: appColors),
        if (widget.workout['planned_duration_minutes'] != null)
          _buildDurationTag(widget.workout['planned_duration_minutes'], appColors),
      ],
    );
  }

  Widget _buildInfoTag({required IconData icon, required String text, required AppColors appColors}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: appColors.sectionBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: appColors.subtleText),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: appColors.subtleText)),
        ],
      ),
    );
  }

  Widget _buildJoinWindowSection(AppColors appColors) {
    final joinMinutes = _joinWindowRemaining ~/ 60;
    final joinSeconds = _joinWindowRemaining % 60;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer, color: Colors.orange[400], size: 22),
              const SizedBox(width: 8),
              Text(
                'Waiting for you to join!',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange[400]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: appColors.sectionBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$joinMinutes:${joinSeconds.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _joinWindowRemaining < 60 ? Colors.red[400] : Colors.orange[400],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('left to join', style: TextStyle(fontSize: 13, color: appColors.subtleText)),
        ],
      ),
    );
  }

  Widget _buildWindowExpiredSection(AppColors appColors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.sectionBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: appColors.subtleText, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${widget.partnerName} started without you',
              style: TextStyle(fontSize: 14, color: appColors.subtleText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuddyCompletedSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, color: Colors.green[400], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.partnerName} completed the workout!',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green[400]),
                ),
                const SizedBox(height: 2),
                Text('Helped the streak grow 🎉', style: TextStyle(fontSize: 12, color: Colors.green[300])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressSection(AppColors appColors) {
    final plannedDuration = widget.workout['planned_duration_minutes'] ?? 30;
    final goalSeconds = plannedDuration * 60;
    final progress = (_workoutElapsed / goalSeconds).clamp(0.0, 1.0);
    final hasReachedGoal = _workoutElapsed >= goalSeconds;

    final elapsedMinutes = _workoutElapsed ~/ 60;
    final elapsedSeconds = _workoutElapsed % 60;

    final remainingSeconds = (goalSeconds - _workoutElapsed).clamp(0, goalSeconds);
    final remainingMinutes = remainingSeconds ~/ 60;
    final remainingSecs = remainingSeconds % 60;

    return GestureDetector(
      onTap: widget.onOpenTimer,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasReachedGoal
              ? Colors.green.withOpacity(0.1)
              : Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasReachedGoal
                ? Colors.green.withOpacity(0.35)
                : Colors.blue.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasReachedGoal ? Icons.check_circle : Icons.timer,
                  color: hasReachedGoal ? Colors.green[400] : Colors.blue[400],
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  '${elapsedMinutes.toString().padLeft(2, '0')}:${elapsedSeconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: hasReachedGoal ? Colors.green[400] : Colors.blue[400],
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasReachedGoal
                        ? Colors.green.withOpacity(0.2)
                        : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '/ ${plannedDuration}m',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasReachedGoal ? Colors.green[300] : Colors.blue[300],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: appColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  hasReachedGoal ? Colors.green[400]! : Colors.blue[400]!,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasReachedGoal
                  ? '🎉 Goal reached! Ready to complete!'
                  : '${remainingMinutes}:${remainingSecs.toString().padLeft(2, '0')} to go',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasReachedGoal ? Colors.green[400] : appColors.subtleText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Text(
            '${widget.workout['creator']?['display_name'] ?? 'Someone'} invited you!',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.of(context).subtleText,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () { HapticFeedback.lightImpact(); widget.onAccept?.call(); },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[500],
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { HapticFeedback.lightImpact(); widget.onDecline?.call(); },
                  icon: Icon(Icons.close, size: 18, color: Colors.red[400]),
                  label: Text('Decline', style: TextStyle(color: Colors.red[400])),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Ready check sections ────────────────────────────────────────────────

  Widget _buildWaitingReadySection(AppColors appColors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Text('🟣', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for ${widget.partnerName}…',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C3AED)),
                ),
                const SizedBox(height: 2),
                Text(
                  "They'll get a notification to confirm",
                  style: TextStyle(fontSize: 11, color: appColors.subtleText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerReadySection(AppColors appColors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department, color: Colors.green[400], size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.partnerName} is ready to go!',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green[400]),
                ),
                const SizedBox(height: 2),
                Text(
                  'Confirm to start the timer together',
                  style: TextStyle(fontSize: 11, color: appColors.subtleText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutActions(String? creatorState, AppColors appColors) {
    if (creatorState == 'window_expired' || creatorState == 'buddy_completed') {
      return const SizedBox.shrink();
    }

    // Join button for waiting state
    if (creatorState == 'waiting_to_join') {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () { HapticFeedback.heavyImpact(); widget.onJoin?.call(); },
                icon: const Icon(Icons.play_arrow, size: 22),
                label: const Text('Join Workout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[500],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () { HapticFeedback.lightImpact(); widget.onCancel?.call(); },
              icon: Icon(Icons.stop_circle_outlined, color: Colors.red[400], size: 16),
              label: Text('Not joining', style: TextStyle(color: Colors.red[400], fontSize: 13)),
            ),
          ],
        ),
      );
    }

    // In progress — complete (locked until goal) + abandon
    if (creatorState == 'in_progress' ||
        (widget.isBuddy && widget.workoutStatus == 'in_progress')) {
      final plannedDuration = widget.workout['planned_duration_minutes'] ?? 30;
      final hasReachedGoal = _workoutElapsed >= (plannedDuration * 60);

      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasReachedGoal
                    ? () { HapticFeedback.heavyImpact(); widget.onComplete?.call(); }
                    : null,
                icon: Icon(hasReachedGoal ? Icons.check_circle : Icons.lock, size: 20),
                label: Text(hasReachedGoal ? 'Complete Workout' : 'Complete Goal First'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasReachedGoal ? Colors.green[500] : appColors.sectionBackground,
                  foregroundColor: hasReachedGoal ? Colors.white : appColors.subtleText,
                  disabledBackgroundColor: appColors.sectionBackground,
                  disabledForegroundColor: appColors.subtleText,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () { HapticFeedback.lightImpact(); widget.onCancel?.call(); },
              icon: Icon(Icons.stop_circle_outlined, color: Colors.red[400], size: 16),
              label: Text('Abandon Workout', style: TextStyle(color: Colors.red[400], fontSize: 13)),
            ),
          ],
        ),
      );
    }

// Creator waiting for buddy — cancel ready option
    if (_creatorWaitingReady) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () { HapticFeedback.lightImpact(); widget.onCancelReady?.call(); },
            style: OutlinedButton.styleFrom(
              foregroundColor: appColors.subtleText,
              side: BorderSide(color: appColors.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cancel ready'),
          ),
        ),
      );
    }

    // Buddy — partner is ready, start together
    if (_buddyCanStartTogether) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () { HapticFeedback.heavyImpact(); widget.onStartTogether?.call(); },
            icon: const Icon(Icons.play_arrow, size: 22),
            label: const Text('Start Together'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[500],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    }

    // Scheduled
    if (widget.workoutStatus == 'scheduled') {
      // ── Buddy workout, creator view ──
      if (_isBuddyWorkout && widget.isCreator) {
        final accepted = widget.buddyStatus == 'accepted';
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: accepted
                    ? GestureDetector(
                        onTap: () { HapticFeedback.heavyImpact(); widget.onReady?.call(); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text("I'm Ready",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      )
                    : Text(
                        'Waiting for ${widget.partnerName} to accept…',
                        style: TextStyle(fontSize: 13, color: appColors.subtleText),
                      ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  onPressed: () { HapticFeedback.lightImpact(); widget.onCancel?.call(); },
                  icon: Icon(Icons.close, color: Colors.red[400]),
                  tooltip: 'Cancel',
                ),
              ),
            ],
          ),
        );
      }

      // ── Buddy workout, buddy view, creator not ready yet ──
      if (_isBuddyWorkout && widget.isBuddy && widget.buddyStatus == 'accepted') {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            "You're in! Waiting for ${widget.partnerName} to get ready…",
            style: TextStyle(fontSize: 13, color: appColors.subtleText),
          ),
        );
      }

      // ── Solo workout — unchanged ──
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () { HapticFeedback.lightImpact(); widget.onStart?.call(); },
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Start Workout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getWorkoutColor(widget.workout['workout_type']),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (widget.isCreator) ...[
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  onPressed: () { HapticFeedback.lightImpact(); widget.onCancel?.call(); },
                  icon: Icon(Icons.close, color: Colors.red[400]),
                  tooltip: 'Cancel',
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Color _getWorkoutColor(String? type) {
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

  IconData _getWorkoutIcon(String? type) {
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final workoutDate = DateTime(date.year, date.month, date.day);
      if (workoutDate == today) return 'Today';
      if (workoutDate == tomorrow) return 'Tomorrow';
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[date.weekday - 1]}, ${date.month}/${date.day}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}