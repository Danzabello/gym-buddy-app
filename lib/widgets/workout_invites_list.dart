import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'workout_schedule_card.dart';

const kInviteLimit = 5;

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Received invites, newest first. [overlaps] holds the accept_workout_invite
/// "overlap" answer per workout id; those rows ask for Accept anyway.
class WorkoutInvitesList extends StatelessWidget {
  final List<Map<String, dynamic>> invites;
  final Map<String, Map<String, dynamic>> overlaps;
  final bool busy;
  final void Function(String id, {bool force}) onAccept;
  final void Function(String id) onDecline;

  const WorkoutInvitesList({
    super.key,
    required this.invites,
    required this.onAccept,
    required this.onDecline,
    this.overlaps = const {},
    this.busy = false,
  });

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _when(DateTime at) {
    final now = DateTime.now();
    final today = at.year == now.year && at.month == now.month && at.day == now.day;
    return today ? hhmm(at) : '${_days[at.weekday - 1]} ${hhmm(at)}';
  }

  @override
  Widget build(BuildContext context) {
    if (invites.isEmpty) return const SizedBox.shrink();
    final c = AppColors.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
              child: Text('Invitations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Text('${invites.length} of $kInviteLimit', style: TextStyle(color: c.subtleText)),
          ]),
          for (final i in invites) _row(context, c, i),
          if (invites.length >= kInviteLimit) ...[
            const SizedBox(height: 8),
            Text('Five invites is the limit. Decline one to make room for the next.',
                style: TextStyle(fontSize: 13, color: c.subtleText)),
          ],
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, AppColors c, Map<String, dynamic> i) {
    final id = i['workout_id'] as String;
    final p = (i['other_person'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = p['display_name'] as String? ?? 'Someone';
    final at = DateTime.parse(i['planned_at'] as String).toLocal();
    final over = overlaps[id];
    final overAt = over == null
        ? null
        : hhmm(DateTime.parse(over['with_planned_at'] as String).toLocal());
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RingAvatar(
            person: Person(
              name: name,
              avatarId: p['avatar_id'] as String?,
              ring: ringFromHex(p['ring_color'] as String?))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_when(at)}, ${i['planned_duration_minutes'] ?? 30} min',
                  style: TextStyle(fontSize: 13, color: c.subtleText)),
            ]),
          ),
        ]),
        if (over != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.warn.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.warn)),
            child: Text(
              'Overlaps with ${over['with_name']} at $overAt. '
              'You can keep both, but only one can run at a time.',
              style: const TextStyle(fontSize: 13)),
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: busy ? null : () => onDecline(id),
              child: const Text('Decline'))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48), backgroundColor: c.streakOrange),
              onPressed: busy ? null : () => onAccept(id, force: over != null),
              child: Text(over != null ? 'Accept anyway' : 'Accept'))),
        ]),
      ]),
    );
  }
}
