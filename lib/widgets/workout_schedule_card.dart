import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/handshake_service.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

/// Everything a button on the card can ask the page to do.
enum CardAction { imHere, cantMakeIt, nudge, goSolo, cancel, leave, abandon, finish, changeTime }

/// One side of the ring: who, and their equipped Ring Color (null = theme default).
class Person {
  final String? name;
  final String? avatarId;
  final Color? ring;
  const Person({this.name, this.avatarId, this.ring});
}

/// Server hex ('#FF6F5E') to a Color. The colour is the user's own equipped
/// Ring Color, so it is data, not a theme token.
Color? ringFromHex(String? hex) {
  final h = hex?.replaceFirst('#', '');
  if (h == null || h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

const kNudgeCooldown = Duration(minutes: 10);

/// Where each avatar sits on the ring, as radians clockwise from 12 o'clock.
/// Both start at the top; whoever taps rides to their place; together they
/// meet at the top.
({double me, double them}) avatarAngles(String state) {
  const apart = 0.3, meet = 0.12;
  switch (state) {
    case 'i_am_here':
      return (me: -math.pi / 2, them: apart);
    case 'buddy_is_here':
      return (me: -apart, them: math.pi / 2);
    case 'running':
    case 'goal_reached':
      return (me: -meet, them: meet);
    case 'solo':
      return (me: 0, them: 0);
    case 'buddy_cant_make_it':
      return (me: -meet, them: math.pi);
    default:
      return (me: -apart, them: apart);
  }
}

class WorkoutScheduleCard extends StatefulWidget {
  final WorkoutCardData data;
  final ServerClock clock;
  final Person me;
  final int streakDays;
  final bool busy;
  final void Function(CardAction) onAction;

  /// Fired once when the clock passes the moment the server state changes by
  /// itself (window opens, goal reached): the page refetches.
  final VoidCallback? onDue;

  const WorkoutScheduleCard({
    super.key,
    required this.data,
    required this.clock,
    required this.me,
    required this.onAction,
    this.streakDays = 0,
    this.busy = false,
    this.onDue,
  });

  @override
  State<WorkoutScheduleCard> createState() => _WorkoutScheduleCardState();
}

class _WorkoutScheduleCardState extends State<WorkoutScheduleCard>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _pulse;
  int _lastSecond = -1;
  String? _dueKey;

  Map<String, dynamic> get _w => widget.data.workout ?? const {};
  String get _state => widget.data.state;
  bool get _iAmCreator => _w['i_am_creator'] == true;
  Map<String, dynamic>? get _other => _w['other_person'] as Map<String, dynamic>?;
  String? get _otherName => _other?['display_name'] as String?;

  DateTime? _t(String k) {
    final v = _w[k] as String?;
    return v == null ? null : DateTime.parse(v);
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _ticker = createTicker((_) {
      final s = widget.clock.now().millisecondsSinceEpoch ~/ 1000;
      if (s == _lastSecond) return;
      _lastSecond = s;
      _checkDue();
      setState(() {});
    })..start();
  }

  @override
  void didUpdateWidget(WorkoutScheduleCard old) {
    super.didUpdateWidget(old);
    const before = {'time_to_start', 'i_am_here', 'buddy_is_here'};
    if (before.contains(old.data.state) &&
        (_state == 'running' || _state == 'goal_reached') &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pulse.forward(from: 0); // M3: one pulse when both are in
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _checkDue() {
    final at = switch (_state) {
      'waiting_start_time' => _t('window_opens_at'),
      'running' || 'solo' => _t('goal_at'),
      _ => null,
    };
    final key = '${_w['workout_id']}:$_state';
    if (at == null || _dueKey == key || widget.clock.now().isBefore(at)) return;
    _dueKey = key;
    widget.onDue?.call();
  }

  Duration get _elapsed {
    final s = _t('workout_started_at');
    return s == null ? Duration.zero : widget.clock.now().difference(s);
  }

  Duration get _goal {
    final s = _t('workout_started_at'), g = _t('goal_at');
    return s != null && g != null
        ? g.difference(s)
        : Duration(minutes: (_w['planned_duration_minutes'] as num?)?.toInt() ?? 30);
  }

  Duration get _nudgeLeft {
    final n = _t('last_nudge_at');
    return n == null ? Duration.zero : n.add(kNudgeCooldown).difference(widget.clock.now());
  }

  static String _startsIn(Duration d) {
    final m = math.max(1, d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0));
    return m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '${m}m';
  }

  String _titleLine() {
    final type = _w['workout_type'] as String? ?? 'Workout';
    final at = _t('planned_at')?.toLocal();
    final time = at == null
        ? ''
        : ', ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return '$type${_otherName == null ? '' : ' with $_otherName'}$time';
  }

  /// (headline, sub line) for the state.
  (String, String) _copy() {
    final n = _otherName ?? 'Your buddy';
    final goal = clockText(_goal);
    switch (_state) {
      case 'solo':
        return ('Keep going', 'Same timer, same ring. Nothing else to tap until the goal.');
      case 'waiting_start_time':
        final left = _t('planned_at')?.difference(widget.clock.now());
        return (
          left == null || left.isNegative ? 'Waiting for $n to accept' : 'Starts in ${_startsIn(left)}',
          ''
        );
      case 'time_to_start':
        return _other == null
            ? ('Time to start', "Tap I'm here to start your timer.")
            : ('$n is in', "Tap I'm here. The timer starts when you both have.");
      case 'i_am_here':
        return ("You're here", 'Waiting for $n. The timer starts the moment $n taps.');
      case 'buddy_is_here':
        return ('$n is here', "Tap I'm here and the timer starts for both of you.");
      case 'running':
        return ('Together with $n', 'Same timer on both phones.');
      case 'goal_reached':
        return ('$goal goal reached', 'You can finish now. Keep going if you want to.');
      case 'buddy_cant_make_it':
        return ("$n can't make it",
            'No penalty for either of you. You can still train on your own today.');
      default:
        return ('', '');
    }
  }

  bool get _dashed => const {'time_to_start', 'i_am_here', 'buddy_is_here'}.contains(_state);
  bool get _running => const {'solo', 'running', 'goal_reached'}.contains(_state);

  // ── menu ───────────────────────────────────────────────────────────────
  List<({CardAction action, String title, String line})> _menuOptions() {
    final n = _otherName ?? 'your buddy';
    final scheduled = !_running;
    if (scheduled && _iAmCreator) {
      return [
        if (_other != null)
          (action: CardAction.changeTime, title: 'Change time',
           line: '$n gets a notification and can accept or decline.'),
        (action: CardAction.cancel, title: 'Cancel workout',
         line: _other == null
             ? 'Cancels this workout.'
             : 'Cancels it for you and $n. $n gets a notification.'),
      ];
    }
    if (scheduled) {
      return [
        (action: CardAction.cantMakeIt, title: "Can't make it",
         line: 'Frees $n up. $n can still work out solo. No penalty.'),
      ];
    }
    if (_state == 'solo' || _other == null) {
      return [
        (action: CardAction.abandon, title: 'Abandon workout',
         line: "Your timer stops and this workout doesn't count."),
      ];
    }
    return [
      (action: CardAction.leave, title: 'Leave workout',
       line: "Your timer stops and this workout doesn't count for you. $n keeps going."),
    ];
  }

  Future<void> _openMenu() async {
    final options = _menuOptions();
    final c = AppColors.of(context);
    final picked = await showModalBottomSheet<CardAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_titleLine().split(',').first,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            for (final o in options) ...[
              _MenuBox(title: o.title, line: o.line, onTap: () => Navigator.pop(ctx, o.action)),
              const SizedBox(height: 8),
            ],
            _MenuBox(title: 'Keep workout', line: null, color: c.subtleText, onTap: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == CardAction.changeTime) return widget.onAction(picked);
    final chosen = options.firstWhere((o) => o.action == picked);
    final title = chosen.title;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: Text(chosen.line),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep workout')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(title)),
        ],
      ),
    );
    if (sure == true && mounted) widget.onAction(picked);
  }

  // ── build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final (headline, sub) = _copy();
    final goalMin = _goal.inMinutes;
    final angles = avatarAngles(_state);
    final progress = _running
        ? (_elapsed.inMilliseconds / math.max(1, _goal.inMilliseconds)).clamp(0.0, 1.0)
        : 0.0;
    final timer = clockText(_running ? _elapsed : Duration.zero);
    final caption = _state == 'goal_reached'
        ? 'Goal reached'
        : _running ? 'of $goalMin min' : '';
    final soloVariant = _state == 'solo' || _other == null || _state == 'buddy_cant_make_it';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Workout Schedule', style: TextStyle(fontSize: 12, color: c.subtleText)),
                const SizedBox(height: 2),
                Text(_titleLine(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
            ),
            IconButton(
              tooltip: 'Workout options',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.more_vert),
              onPressed: widget.busy ? null : _openMenu,
            ),
          ]),
          const SizedBox(height: 12),
          Center(
            child: SizedBox.square(
              dimension: 220,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: const Size.square(220),
                  painter: _RingPainter(
                    progress: progress, dashed: _dashed,
                    track: c.divider, fill: scheme.primary),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(timer, style: const TextStyle(
                      fontSize: 38, fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()])),
                  if (caption.isNotEmpty)
                    Text(caption, style: TextStyle(fontSize: 13, color: c.subtleText)),
                ]),
                if (_other != null)
                  _RingAvatar(
                    angle: angles.them, reduce: reduce, pulse: _pulse,
                    person: Person(
                      name: _otherName,
                      avatarId: _other!['avatar_id'] as String?,
                      ring: ringFromHex(_other!['ring_color'] as String?)),
                    dim: _state == 'buddy_cant_make_it'),
                _RingAvatar(angle: angles.me, reduce: reduce, pulse: _pulse, person: widget.me),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(headline, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: c.subtleText)),
          ],
          const SizedBox(height: 16),
          ..._buttons(c),
          if (_state == 'running' || _state == 'solo') ...[
            const SizedBox(height: 4),
            Text('Finish unlocks at ${clockText(_goal)}',
                textAlign: TextAlign.center, style: TextStyle(color: c.subtleText)),
          ],
          if (widget.streakDays > 0) ...[
            const SizedBox(height: 12),
            Text(
              soloVariant
                  ? 'Day ${widget.streakDays} streak: a solo workout today keeps it alive'
                  : 'Day ${widget.streakDays} streak: this workout keeps it alive',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.subtleText)),
          ],
        ]),
      ),
    );
  }

  List<Widget> _buttons(AppColors c) {
    final n = _otherName ?? 'your buddy';
    final off = widget.busy;
    Widget primary(String label, CardAction? a) => FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48), backgroundColor: c.streakOrange),
          onPressed: a == null || off ? null : () => widget.onAction(a),
          child: Text(label),
        );
    Widget secondary(String label, CardAction? a) => OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: a == null || off ? null : () => widget.onAction(a),
          child: Text(label),
        );
    const gap = SizedBox(height: 8);
    switch (_state) {
      case 'time_to_start':
        return [primary("I'm here", CardAction.imHere),
          if (!_iAmCreator) ...[gap, secondary("Can't make it", CardAction.cantMakeIt)]];
      case 'buddy_is_here':
        return [primary("I'm here, start the timer", CardAction.imHere),
          if (!_iAmCreator) ...[gap, secondary("Can't make it", CardAction.cantMakeIt)]];
      case 'i_am_here':
        final left = _nudgeLeft;
        return [primary('Waiting for $n', null), gap,
          secondary(left > Duration.zero ? 'Nudge $_otherName, ${clockText(left)}' : 'Nudge $_otherName',
              left > Duration.zero ? null : CardAction.nudge)];
      case 'goal_reached':
        return [FinishButton(onPressed: off ? null : () => widget.onAction(CardAction.finish))];
      case 'buddy_cant_make_it':
        return [primary('Go solo', CardAction.goSolo), gap, secondary('Cancel workout', CardAction.cancel)];
      default:
        return const [];
    }
  }
}

class _MenuBox extends StatelessWidget {
  final String title;
  final String? line;
  final Color? color;
  final VoidCallback onTap;
  const _MenuBox({required this.title, required this.line, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: c.cardBorder),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          if (line != null) ...[
            const SizedBox(height: 2),
            Text(line!, style: TextStyle(fontSize: 13, color: c.subtleText)),
          ],
        ]),
      ),
    );
  }
}

/// Avatar parked on the ring at [angle]; it rides there when the angle changes (M2).
class _RingAvatar extends StatelessWidget {
  final double angle;
  final bool reduce, dim;
  final Animation<double> pulse;
  final Person person;
  const _RingAvatar({
    required this.angle, required this.reduce, required this.pulse,
    required this.person, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: angle),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      builder: (_, a, __) => Transform.translate(
        offset: Offset(math.sin(a) * 100, -math.cos(a) * 100),
        child: AnimatedBuilder(
          animation: pulse,
          builder: (_, child) =>
              Transform.scale(scale: 1 + 0.15 * math.sin(pulse.value * math.pi), child: child),
          child: Opacity(opacity: dim ? 0.4 : 1, child: RingAvatar(person: person, size: 44)),
        ),
      ),
    );
  }
}

/// Real avatar inside a glow in the user's equipped Ring Color (theme primary if none).
class RingAvatar extends StatelessWidget {
  final Person person;
  final double size;
  const RingAvatar({super.key, required this.person, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final ring = person.ring ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.of(context).cardBackground,
        border: Border.all(color: ring, width: 3),
        boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.5), blurRadius: 10)],
      ),
      child: ClipOval(child: UserAvatar(avatarId: person.avatarId, size: size - 6, bare: true)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool dashed;
  final Color track, fill;
  const _RingPainter({required this.progress, required this.dashed, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(14);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = track..strokeCap = StrokeCap.round;
    if (dashed) {
      const n = 36;
      for (var i = 0; i < n; i++) {
        canvas.drawArc(r, -math.pi / 2 + i * 2 * math.pi / n, math.pi / n, false, p);
      }
    } else {
      canvas.drawArc(r, 0, 2 * math.pi, false, p);
      canvas.drawArc(r, -math.pi / 2, 2 * math.pi * progress, false, p..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress || o.dashed != dashed || o.track != track || o.fill != fill;
}

/// M4: one button. Grey label, an orange layer wipes across it left to right
/// (clipped), then the button glows twice. No motion when animations are off.
class FinishButton extends StatefulWidget {
  final VoidCallback? onPressed;
  const FinishButton({super.key, required this.onPressed});

  @override
  State<FinishButton> createState() => _FinishButtonState();
}

class _FinishButtonState extends State<FinishButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctl.value = 1;
    } else {
      _ctl.forward();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final t = _ctl.value;
        final wipe = Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0)); // first 40%
        final glow = t < 0.4 ? 0.0 : math.pow(math.sin((t - 0.4) / 0.6 * 2 * math.pi), 2).toDouble();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: c.streakOrange.withValues(alpha: 0.6 * glow), blurRadius: 18)],
          ),
          child: Material(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              child: SizedBox(
                height: 48,
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: wipe,
                        child: ColoredBox(key: const Key('finish_wipe'), color: c.streakOrange),
                      ),
                    ),
                  ),
                  Text('Finish workout',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color.lerp(c.subtleText, Colors.white, wipe))),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
