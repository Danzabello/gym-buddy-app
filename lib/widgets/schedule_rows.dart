import 'package:flutter/material.dart';

import '../services/handshake_service.dart';
import '../theme/app_theme.dart';
import '../utils/workout_time.dart';
import 'workout_schedule_card.dart';

String _title(Map<String, dynamic> w) {
  final type = w['workout_type'] as String? ?? 'Workout';
  final n = (w['other_person'] as Map?)?['display_name'] as String?;
  return n == null ? type : '$type with $n';
}

Person _other(Map<String, dynamic> w) {
  final p = (w['other_person'] as Map?)?.cast<String, dynamic>();
  return Person(
      name: p?['display_name'] as String?,
      avatarId: p?['avatar_id'] as String?,
      ring: ringFromHex(p?['ring_color'] as String?));
}

/// States that get the highlighted "Now" row.
const nowStates = {
  'time_to_start', 'i_am_here', 'buddy_is_here', 'running', 'goal_reached', 'buddy_cant_make_it', 'solo'
};

/// Status line of a Now row. [now] is server time, so the running clock is
/// the server's.
String nowStatus(Map<String, dynamic> w, DateTime now) {
  final n = (w['other_person'] as Map?)?['display_name'] as String? ?? 'Your buddy';
  switch (w['state']) {
    case 'i_am_here': return 'Waiting for $n';
    case 'buddy_is_here': return '$n is here';
    case 'running' || 'solo':
      final s = w['workout_started_at'] as String?;
      return 'Running ${clockText(s == null ? Duration.zero : now.difference(DateTime.parse(s)))}';
    case 'goal_reached': return 'Goal reached';
    case 'buddy_cant_make_it': return "$n can't make it";
    default: return 'Time to start';
  }
}

class NowRow extends StatelessWidget {
  final Map<String, dynamic> workout;
  final Person me;
  final DateTime now;
  final VoidCallback onTap;
  const NowRow({super.key, required this.workout, required this.me, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final hasOther = workout['other_person'] != null;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: BorderSide(color: primary, width: 1.5)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(
              width: hasOther ? 70 : 44,
              height: 44,
              child: Stack(children: [
                RingAvatar(person: me, size: 40),
                if (hasOther) Positioned(left: 26, child: RingAvatar(person: _other(workout), size: 40)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Now', style: TextStyle(fontSize: 12, color: c.subtleText)),
                Text(_title(workout), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(nowStatus(workout, now), style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class UpcomingRow extends StatelessWidget {
  final Map<String, dynamic> workout;
  final Person me;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  const UpcomingRow({
    super.key, required this.workout, required this.me, required this.now,
    required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final at = DateTime.parse(workout['planned_at'] as String);
    final left = at.difference(now);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            RingAvatar(person: workout['other_person'] == null ? me : _other(workout), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title(workout), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: c.subtleText), children: [
                  TextSpan(text: '${whenText(at, now)} · '),
                  TextSpan(
                      text: left.isNegative || left.inSeconds == 0 ? 'time to start' : 'starts in ${startsInText(left)}',
                      style: TextStyle(color: c.successGreen, fontWeight: FontWeight.w600)),
                ])),
              ]),
            ),
            IconButton(
              tooltip: 'Workout options',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.more_vert),
              onPressed: onMenu,
            ),
          ]),
        ),
      ),
    );
  }
}
