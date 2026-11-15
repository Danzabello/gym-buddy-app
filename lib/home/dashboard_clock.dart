import 'dart:math';

import 'package:flutter/widgets.dart';

/// Where the dashboard reads the time. Injected so a test can drive it.
typedef Clock = DateTime Function();

/// The wall-clock hour [now] falls in, counted in hours. Local time, so the
/// bucket turns when the phone's clock shows a new hour, also in zones that
/// sit half an hour off UTC.
int hourBucketOf(DateTime now) =>
    (now.millisecondsSinceEpoch + now.timeZoneOffset.inMilliseconds) ~/
    Duration.millisecondsPerHour;

/// Which of [count] coach tips to show. A pure function of the hour and the
/// seed: any number of rebuilds inside one hour pick the same tip.
int pickCoachTip({
  required int hourBucket,
  required int seed,
  required int count,
}) =>
    Random(hourBucket * 1000003 + seed).nextInt(count);

/// The coach tip's session record: the tip changes when the hour turns and
/// when the app comes back from the background, and on nothing else. Lives
/// outside the dashboard's State because the tab PageView disposes that State
/// when another tab is open.
class CoachTipRotation {
  static final session = CoachTipRotation();

  int _seed = 0;
  bool _wasHidden = false;

  /// The app left the screen (lifecycle `hidden`). A pulled-down shade or a
  /// permission dialog only reaches `inactive`, which is not a background trip.
  void onHidden() => _wasHidden = true;

  /// A resume draws a fresh tip only after a real trip to the background.
  void onResumed() {
    if (!_wasHidden) return;
    _wasHidden = false;
    _seed++;
  }

  int indexAt(DateTime now, int count) =>
      pickCoachTip(hourBucket: hourBucketOf(now), seed: _seed, count: count);
}

/// One clock-dependent part of the dashboard. It rebuilds its own subtree, and
/// nothing above it, when [tick] fires. [builder] gets the time read from
/// [clock] at that build, so a rebuild from above shows the same value a tick
/// would.
class ClockPart extends StatefulWidget {
  const ClockPart({
    super.key,
    required this.tick,
    required this.clock,
    this.select,
    required this.builder,
  });

  final Listenable tick;
  final Clock clock;

  /// What the part takes from the clock. With it, a tick rebuilds the part
  /// only when this value differs from the one the part was last built from.
  /// Without it, every tick rebuilds the part.
  final Object? Function(DateTime now)? select;

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<ClockPart> createState() => _ClockPartState();
}

class _ClockPartState extends State<ClockPart> {
  Object? _built;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_onTick);
  }

  @override
  void didUpdateWidget(ClockPart old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) {
      old.tick.removeListener(_onTick);
      widget.tick.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    final select = widget.select;
    if (select == null || select(widget.clock()) != _built) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    _built = widget.select?.call(now);
    return widget.builder(context, now);
  }
}
