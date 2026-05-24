// lib/widgets/schedule_workout_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/workout_invite_service.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

class ScheduleWorkoutDialog extends StatefulWidget {
  final Map<String, dynamic> friendProfile;
  const ScheduleWorkoutDialog(
      {super.key, required this.friendProfile});

  @override
  State<ScheduleWorkoutDialog> createState() =>
      _ScheduleWorkoutDialogState();
}

class _ScheduleWorkoutDialogState
    extends State<ScheduleWorkoutDialog> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSending = false;

  bool get _hasDateTime =>
      _selectedDate != null && _selectedTime != null;

  Future<void> _pickDateTime() async {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: isDark
              ? ColorScheme.dark(
                  primary: const Color(0xFF3B82F6),
                  onPrimary: Colors.white,
                  surface: appColors.cardBackground,
                  onSurface: cs.onSurface,
                )
              : ColorScheme.light(
                  primary: const Color(0xFF1D4ED8),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: isDark
              ? ColorScheme.dark(
                  primary: const Color(0xFF3B82F6),
                  onPrimary: Colors.white,
                  surface: appColors.cardBackground,
                  onSurface: cs.onSurface,
                )
              : ColorScheme.light(
                  primary: const Color(0xFF1D4ED8),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  Future<void> _send({required bool isToday}) async {
    setState(() => _isSending = true);
    try {
      final currentUserId =
          Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final friendName =
          widget.friendProfile['display_name'] ?? 'your friend';

      DateTime scheduledAt;
      String message;

      if (isToday) {
        scheduledAt = DateTime.now();
        message = 'Hey! Let\'s workout together today! 💪';
      } else {
        scheduledAt = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
        message =
            'Workout scheduled for ${_formatDateTime(scheduledAt)}';
      }

      final service = WorkoutInviteService();
      final invite = await service.sendInvite(
        recipientId: widget.friendProfile['id'],
        scheduledFor: scheduledAt,
        message: message,
      );

      if (invite == null) throw Exception('Failed to send invite');

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(isToday
                ? 'Workout invite sent to $friendName! 🎉'
                : 'Workout scheduled with $friendName! 📅'),
          ),
        ]),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to send workout invite'),
        backgroundColor: Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    String dateStr;
    if (diff.inDays == 0) {
      dateStr = 'Today';
    } else if (diff.inDays == 1) {
      dateStr = 'Tomorrow';
    } else {
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      dateStr =
          '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
    }
    final h = dt.hour == 0
        ? 12
        : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$dateStr at $h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final friendName =
        widget.friendProfile['display_name'] ?? 'Buddy';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Gradient header ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2),
                    color: Colors.white.withOpacity(0.12),
                  ),
                  child: ClipOval(
                    child: UserAvatar(
                      avatarId: widget.friendProfile['avatar_id'],
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Workout with',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500)),
                      Text(friendName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white),
                  ),
                ),
              ]),
            ),

            // ── Workout Today CTA ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: GestureDetector(
                onTap: _isSending ? null : () => _send(isToday: true),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('⚡',
                            style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Workout Today!',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          Text('Send a quick invite for right now',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Colors.white70, size: 20),
                  ]),
                ),
              ),
            ),

            // ── OR divider ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(children: [
                Expanded(
                    child: Container(
                        height: 0.5, color: appColors.divider)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('OR SCHEDULE',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: appColors.subtleText)),
                ),
                Expanded(
                    child: Container(
                        height: 0.5, color: appColors.divider)),
              ]),
            ),

            // ── Schedule for later ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PICK A DATE & TIME',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: appColors.subtleText)),
                  const SizedBox(height: 8),

                  // Date/time picker button
                  GestureDetector(
                    onTap: _pickDateTime,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: _hasDateTime
                            ? const Color(0xFF3B82F6).withOpacity(0.08)
                            : appColors.sectionBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hasDateTime
                              ? const Color(0xFF3B82F6).withOpacity(0.3)
                              : appColors.cardBorder,
                          width: 0.5,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today,
                            size: 16,
                            color: _hasDateTime
                                ? const Color(0xFF3B82F6)
                                : appColors.subtleText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _hasDateTime
                                ? _formatDateTime(DateTime(
                                    _selectedDate!.year,
                                    _selectedDate!.month,
                                    _selectedDate!.day,
                                    _selectedTime!.hour,
                                    _selectedTime!.minute,
                                  ))
                                : 'Pick Date & Time',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _hasDateTime
                                  ? const Color(0xFF3B82F6)
                                  : appColors.subtleText,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 16,
                            color: appColors.subtleText),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Send invite button
                  GestureDetector(
                    onTap: (_hasDateTime && !_isSending)
                        ? () => _send(isToday: false)
                        : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _hasDateTime ? 1.0 : 0.35,
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('Send Invite 📅',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Cancel ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GestureDetector(
                onTap: _isSending
                    ? null
                    : () => Navigator.pop(context),
                child: Text('Cancel',
                    style: TextStyle(
                        fontSize: 13,
                        color: appColors.subtleText)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}