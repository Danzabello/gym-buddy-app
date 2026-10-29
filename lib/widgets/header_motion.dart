import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gym_buddy_app/services/level_service.dart';

/// The "x/y" denominator the header shows for a level.
int headerLevelWidth(LevelInfo i) => i.xpForNextLevel - i.xpForThisLevel;

/// What the header's semantics say, always from the target numbers.
String headerSemanticLabel(int coins, LevelInfo i) =>
    'Coins $coins, level ${i.level}, ${i.xpIntoCurrentLevel} of ${headerLevelWidth(i)} XP';

enum HeaderStepKind { fill, levelUp, remainder }

/// One beat of the XP motion. [fill] and [remainder] count xp [fromXp] to
/// [toXp] inside a level of [width]; [levelUp] is the pop, with the label
/// jumping to [level] and the bar switching to the new level's [width].
class HeaderStep {
  const HeaderStep(
    this.kind, {
    this.fromXp = 0,
    this.toXp = 0,
    this.width = 0,
    this.level = 0,
  });

  final HeaderStepKind kind;
  final int fromXp;
  final int toXp;
  final int width;
  final int level;

  @override
  bool operator ==(Object other) =>
      other is HeaderStep &&
      other.kind == kind &&
      other.fromXp == fromXp &&
      other.toXp == toXp &&
      other.width == width &&
      other.level == level;

  @override
  int get hashCode => Object.hash(kind, fromXp, toXp, width, level);

  @override
  String toString() =>
      'HeaderStep($kind, $fromXp->$toXp of $width, level $level)';
}

/// Ordered xp steps from [old] to [next]. Empty means nothing to animate
/// (no xp change, or a level that went down): the caller snaps.
/// A credit that crosses several levels is one level-up beat: the old level's
/// width fills to full, the number jumps straight to the new level, and the
/// new level's width fills the remainder.
List<HeaderStep> planHeaderSteps(LevelInfo old, LevelInfo next) {
  if (next.level < old.level) return const [];
  final oldInto = old.xpIntoCurrentLevel;
  final newInto = next.xpIntoCurrentLevel;
  final oldWidth = headerLevelWidth(old);
  if (next.level == old.level) {
    if (newInto == oldInto) return const [];
    return [
      HeaderStep(
        HeaderStepKind.fill,
        fromXp: oldInto,
        toXp: newInto,
        width: oldWidth,
      ),
    ];
  }
  final newWidth = headerLevelWidth(next);
  return [
    HeaderStep(
      HeaderStepKind.fill,
      fromXp: oldInto,
      toXp: oldWidth,
      width: oldWidth,
    ),
    HeaderStep(HeaderStepKind.levelUp, width: newWidth, level: next.level),
    if (newInto > 0)
      HeaderStep(HeaderStepKind.remainder, toXp: newInto, width: newWidth),
  ];
}

/// Drives the dashboard header's coin count, XP bar and level-up pop. Owns its
/// controllers and timers; call [dispose]. Widgets listen to it directly.
class HeaderMotion extends ChangeNotifier {
  HeaderMotion(TickerProvider vsync, {this.onSettled})
    : _coin = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 800),
        value: 1,
      ),
      _bar = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 700),
        value: 1,
      ),
      _ring = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 1000),
      ),
      _pop = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 600),
      ) {
    for (final c in [_coin, _bar, _ring, _pop]) {
      c.addListener(notifyListeners);
    }
    _coin.addStatusListener(_onDone);
    _bar.addStatusListener(_onDone);
  }

  /// Called once after the last step of an animated credit.
  final VoidCallback? onSettled;

  static const _ease = Curves.easeOutCubic;

  final AnimationController _coin;
  final AnimationController _bar;
  final AnimationController _ring;
  final AnimationController _pop;

  bool ready = false;
  LevelInfo? target;
  int coinTarget = 0;
  int level = 1;
  int width = 1;

  int _coinFrom = 0;
  int _coinTo = 0;
  double _fromXp = 0;
  double _toXp = 0;

  bool _sweepPending = false;
  bool _beat = false;
  LevelInfo? _pending;
  bool _announce = false;
  int _gen = 0;
  bool _disposed = false;
  final Set<Timer> _timers = {};

  int get coins =>
      (_coinFrom + (_coinTo - _coinFrom) * _ease.transform(_coin.value))
          .round();

  double get _xpExact =>
      _fromXp + (_toXp - _fromXp) * _ease.transform(_bar.value);
  int get xp => _xpExact.round();
  double get fraction => (_xpExact / math.max(1, width)).clamp(0.0, 1.0);

  bool get popping => _pop.isAnimating;

  /// 1 to 1.22 in 280 ms, back to 1 in 320 ms.
  double get popScale {
    if (!_pop.isAnimating) return 1;
    const peak = 280 / 600;
    final t = _pop.value;
    return t <= peak
        ? 1 + 0.22 * _ease.transform(t / peak)
        : 1.22 - 0.22 * _ease.transform((t - peak) / (1 - peak));
  }

  /// 0 to 1 in 240 ms, then 1 to 0 in 760 ms.
  double get ringOpacity {
    if (!_ring.isAnimating) return 0;
    final t = _ring.value;
    return t < 0.24
        ? _ease.transform(t / 0.24)
        : 1 - _ease.transform((t - 0.24) / 0.76);
  }

  /// True when [i] and [coins] are what this motion is already showing or
  /// heading to.
  bool matches(LevelInfo i, int coins) {
    final t = target;
    return t != null &&
        coins == coinTarget &&
        t.level == i.level &&
        t.xpIntoCurrentLevel == i.xpIntoCurrentLevel &&
        headerLevelWidth(t) == headerLevelWidth(i);
  }

  /// First real value. Safe to call during build (no notifications). With
  /// [sweep] the bar sits empty, then fills to the value after 600 ms.
  void init(LevelInfo info, int coins, {required bool sweep}) {
    ready = true;
    target = info;
    level = info.level;
    width = headerLevelWidth(info);
    coinTarget = _coinFrom = _coinTo = coins;
    _fromXp = _toXp = sweep ? 0 : info.xpIntoCurrentLevel.toDouble();
    if (sweep) {
      _sweepPending = true;
      _later(600, _startSweep);
    }
  }

  void _startSweep() {
    final t = target;
    if (t == null) return;
    _sweepPending = false;
    level = t.level;
    width = headerLevelWidth(t);
    _animateBar(t.xpIntoCurrentLevel.toDouble(), 1000);
    notifyListeners();
  }

  /// Jump to the numbers with no motion (resume, hidden screen, reduced motion).
  void snap(LevelInfo info, int coins) {
    _gen++;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _beat = false;
    _pending = null;
    _sweepPending = false;
    _announce = false;
    _ring.stop();
    _pop.stop();
    _coin.stop();
    _bar.stop();
    ready = true;
    target = info;
    level = info.level;
    width = headerLevelWidth(info);
    coinTarget = _coinFrom = _coinTo = coins;
    _fromXp = _toXp = info.xpIntoCurrentLevel.toDouble();
    _bar.value = 1;
    _coin.value = 1;
    notifyListeners();
  }

  /// The server reported new numbers and the screen is visible.
  void credit(LevelInfo next, int newCoins) {
    if (!ready) return;
    if (newCoins != coinTarget) {
      final up = newCoins > coinTarget;
      _coinFrom = coins; // retarget from the number on screen
      _coinTo = coinTarget = newCoins;
      _announce = true;
      _coin.forward(from: 0);
      if (up) _ring.forward(from: 0);
    }
    final old = target!;
    target = next;
    if (_sweepPending) return;
    if (_beat) {
      _pending = next;
      return;
    }
    _play(old, next);
  }

  void _play(LevelInfo old, LevelInfo next) {
    final plan = planHeaderSteps(old, next);
    if (plan.isEmpty) {
      if (next.level != level || headerLevelWidth(next) != width) {
        _bar.stop();
        level = next.level;
        width = headerLevelWidth(next);
        _fromXp = _toXp = next.xpIntoCurrentLevel.toDouble();
        _bar.value = 1;
      }
      _settle();
      return;
    }
    _announce = true;
    if (plan.length == 1) {
      width = plan[0].width;
      _animateBar(plan[0].toXp.toDouble(), 700);
      return;
    }
    _levelUp(plan, next);
  }

  Future<void> _levelUp(List<HeaderStep> plan, LevelInfo next) async {
    final gen = _gen;
    _beat = true;
    width = plan[0].width;
    await _animateBar(plan[0].toXp.toDouble(), 600);
    if (_stale(gen)) return;
    // Full: pop, swap the number at the peak, hold 840 ms from this moment.
    _pop.forward(from: 0);
    _later(280, () {
      level = next.level;
      notifyListeners();
    });
    await _wait(840);
    if (_stale(gen)) return;
    width = plan[1].width;
    _bar.stop();
    _fromXp = _toXp = 0;
    _bar.value = 1;
    if (plan.length > 2) {
      await _animateBar(plan[2].toXp.toDouble(), 700);
      if (_stale(gen)) return;
    }
    _beat = false;
    final p = _pending;
    _pending = null;
    if (p != null) {
      _play(next, p);
    } else {
      _settle();
    }
  }

  TickerFuture _animateBar(double toXp, int ms) {
    _fromXp = _xpExact;
    _toXp = toXp;
    _bar.duration = Duration(milliseconds: ms);
    return _bar.forward(from: 0);
  }

  bool _stale(int gen) => _disposed || gen != _gen;

  void _onDone(AnimationStatus s) {
    if (s == AnimationStatus.completed) _settle();
  }

  /// One announcement once every part of an animated credit has landed.
  void _settle() {
    if (!_announce || _disposed || _beat || _sweepPending || _pending != null) {
      return;
    }
    if (_coin.isAnimating || _bar.isAnimating) return;
    _announce = false;
    onSettled?.call();
  }

  void _later(int ms, VoidCallback f) {
    late final Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (!_disposed) f();
    });
    _timers.add(t);
  }

  Future<void> _wait(int ms) {
    final c = Completer<void>();
    _later(ms, c.complete);
    return c.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _coin.dispose();
    _bar.dispose();
    _ring.dispose();
    _pop.dispose();
    super.dispose();
  }
}

const _tabular = [FontFeature.tabularFigures()];

/// The coin number. Fixed minimum width so the pill does not resize while
/// counting; the ticking digits stay out of semantics.
class HeaderCoinCount extends StatelessWidget {
  const HeaderCoinCount({
    super.key,
    required this.motion,
    required this.style,
    required this.fallback,
  });

  final HeaderMotion motion;
  final TextStyle style;

  /// Shown until the motion has its first value.
  final int fallback;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 34),
        child: AnimatedBuilder(
          animation: motion,
          builder: (_, __) => Text(
            '${motion.ready ? motion.coins : fallback}',
            style: style.copyWith(fontFeatures: _tabular),
          ),
        ),
      ),
    );
  }
}

/// A 2 px outline just outside its parent (use inside a Positioned.fill with
/// negative insets). Opacity only.
class HeaderCoinRing extends StatelessWidget {
  const HeaderCoinRing({super.key, required this.motion, required this.color});

  final HeaderMotion motion;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: motion,
        builder: (_, __) => Opacity(
          opacity: motion.ringOpacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The XP bar and its "LV n · x/y XP ... LV n+1" row, driven by [motion].
class HeaderXpRow extends StatelessWidget {
  const HeaderXpRow({
    super.key,
    required this.motion,
    required this.semanticLabel,
    required this.track,
    required this.fill,
    required this.textColor,
    required this.popColor,
  });

  final HeaderMotion motion;
  final String semanticLabel;
  final Color track;
  final Color fill;
  final Color textColor;
  final Color popColor;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: textColor,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      fontFeatures: _tabular,
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: motion,
        builder: (_, __) {
          final pop = base.copyWith(
            color: motion.popping ? popColor : textColor,
          );
          Widget label(String s) => Transform.scale(
            scale: motion.popScale,
            alignment: Alignment.centerLeft,
            child: Text(s, style: pop),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: motion.fraction,
                  minHeight: 6,
                  backgroundColor: track,
                  valueColor: AlwaysStoppedAnimation<Color>(fill),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      label('LV ${motion.level}'),
                      Text(' · ${motion.xp}/${motion.width} XP', style: base),
                    ],
                  ),
                  label('LV ${motion.level + 1}'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
