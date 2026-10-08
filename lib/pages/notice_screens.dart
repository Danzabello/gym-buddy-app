import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/accent_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/live_event_toast.dart' show appNavigatorKey;

// ── Model ─────────────────────────────────────────────────────────────────
// Parses get_pending_notice(). The server returns ONE kind, already
// prioritised (many > own > friend > auto_completed); `others` counts the
// lower-priority notices still pending.

class NoticeItem {
  final String id;
  final String kind; // 'own' | 'friend' | 'auto'
  final int lost;
  final String buddy;
  final String missedName;
  final int? best;
  final int? minutes;
  final String? date; // yyyy-MM-dd

  const NoticeItem({
    required this.id,
    required this.kind,
    this.lost = 0,
    this.buddy = 'your buddy',
    this.missedName = 'your buddy',
    this.best,
    this.minutes,
    this.date,
  });

  factory NoticeItem.fromJson(Map<String, dynamic> j, {String? kind}) {
    final k = kind ?? j['kind'] as String? ?? 'own';
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return s == null || s.isEmpty ? null : s;
    }

    final buddy = clean(j['buddy_name']) ??
        (j['is_coach_max_team'] == true ? 'Coach Max' : clean(j['team_name'])) ??
        'your buddy';
    return NoticeItem(
      id: j['id'] as String,
      kind: k,
      lost: (j['lost_streak'] as num?)?.toInt() ?? 0,
      buddy: buddy,
      missedName: clean(j['missed_name']) ?? buddy,
      best: (j['best_streak'] as num?)?.toInt(),
      minutes: (j['minutes'] as num?)?.toInt(),
      date: j['workout_date'] as String?,
    );
  }
}

class Notice {
  final String kind; // 'many' | 'own' | 'friend' | 'auto_completed'
  final List<NoticeItem> items;
  final int others;
  const Notice(this.kind, this.items, this.others);

  List<String> get ids => [for (final i in items) i.id];

  /// null when there is nothing to show.
  static Notice? parse(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'] as String?;
    final list = (raw['items'] as List?) ?? const [];
    if (kind == null || list.isEmpty) return null;
    final items = [
      for (final e in list)
        NoticeItem.fromJson(Map<String, dynamic>.from(e as Map),
            kind: kind == 'auto_completed' ? 'auto' : null),
    ];
    return Notice(kind, items, (raw['others'] as num?)?.toInt() ?? 0);
  }
}

/// Darkens [fg] until it reads on [bg] (4.5:1). Dark skins pass untouched.
Color readableOn(Color fg, Color bg) {
  double ratio(Color a) {
    final x = a.computeLuminance() + 0.05, y = bg.computeLuminance() + 0.05;
    return x > y ? x / y : y / x;
  }

  final hsl = HSLColor.fromColor(fg);
  var l = hsl.lightness;
  var out = fg;
  while (ratio(out) < 4.5 && l > 0.05) {
    l -= 0.02;
    out = hsl.withLightness(l).toColor();
  }
  return out;
}

String daysLabel(int n) => '$n ${n == 1 ? 'day' : 'days'}';

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

String countedFor(String? date, DateTime now) {
  final d = date == null ? null : DateTime.tryParse(date);
  if (d == null || (d.year == now.year && d.month == now.month && d.day == now.day)) {
    return 'Today';
  }
  return _weekdays[d.weekday - 1];
}

// ── Host: one check per app open / resume, plus the quiet Home card ───────

class NoticeHomeCard extends StatefulWidget {
  const NoticeHomeCard({super.key});

  @override
  State<NoticeHomeCard> createState() => _NoticeHomeCardState();
}

class _NoticeHomeCardState extends State<NoticeHomeCard>
    with WidgetsBindingObserver {
  // Static: the dashboard can rebuild this widget (loading skeleton), but the
  // check is once per app open and the open flag must outlive the State.
  static bool _busy = false;
  static bool _checkedThisOpen = false;
  static final ValueNotifier<int> _others = ValueNotifier(0);
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_checkedThisOpen) {
      _checkedThisOpen = true;
      _check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wasPaused = true;
    if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      _check();
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    _busy = true;
    try {
      final raw = await Supabase.instance.client.rpc('get_pending_notice');
      final notice = Notice.parse(raw);
      if (notice == null) {
        _others.value = 0;
        return;
      }
      // The navigator's own context can't find a Navigator; its overlay can.
      final ctx = appNavigatorKey.currentState?.overlay?.context;
      if (ctx == null) return;
      _others.value = 0;
      await showDialog<void>(
        // ignore: use_build_context_synchronously
        context: ctx, // overlay of a global key, not a widget context
        builder: (_) => NoticeDialog(notice),
      );
      _others.value = notice.others;
    } catch (_) {
      // Offline / 401: no screen, no snackbar.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _others,
      builder: (context, n, _) {
        if (n <= 0) return const SizedBox.shrink();
        final c = AppColors.of(context);
        final violet = context.read<AccentThemeProvider>().palette.secondaryAccent;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.only(left: 16, right: 4),
          decoration: BoxDecoration(
            color: c.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cardBorder, width: 0.5),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                n == 1 ? 'You have 1 more update' : 'You have $n more updates',
                style: TextStyle(color: c.subtleText, fontSize: 14),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 44), foregroundColor: violet),
              onPressed: _check,
              child: const Text('View', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      },
    );
  }
}


// ── Dialog (same shell as the Monday _WeeklyPlanDialog) ───────────────────

/// Same orange as _WeeklyPlanDialog's label and button.
const _kOrange = Color(0xFFF97316);

Future<void> _markSeen(List<String> ids) =>
    Supabase.instance.client.rpc('mark_notice_seen', params: {'p_ids': ids});

class NoticeDialog extends StatefulWidget {
  final Notice notice;
  final Future<void> Function(List<String> ids) onSeen;
  const NoticeDialog(this.notice, {super.key, this.onSeen = _markSeen});

  @override
  State<NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<NoticeDialog> {
  bool _closing = false;

  // Button, Back and barrier tap all land here (PopScope blocks the plain pop).
  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    final nav = Navigator.of(context);
    try {
      await widget.onSeen(widget.notice.ids);
    } catch (_) {
      // Server keeps it pending; it shows again on the next open.
    }
    if (nav.mounted) nav.pop();
  }

  static String _short(String name) {
    final u = name.toUpperCase();
    return u.length > 14 ? '${u.substring(0, 13)}…' : u;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final violet = context.read<AccentThemeProvider>().palette.secondaryAccent;
    final n = widget.notice;
    final first = n.items.first;
    // The skin's success green is too pale for a light card.
    final green = readableOn(c.success, c.cardBackground);

    late final String label, line1, line2, body;
    late final Color line2Color;
    NoticeHeroKind? heroKind;
    var heroValue = 0;
    Color heroColor = c.danger;
    String? caption, tip;
    Color boxColor = c.danger;
    List<Widget>? rows;
    List<NoticeItem>? list;

    switch (n.kind) {
      case 'auto_completed':
        label = 'AUTO CHECK-IN';
        line1 = 'CHECK-IN';
        line2 = 'COMPLETED';
        line2Color = green;
        heroKind = NoticeHeroKind.tick;
        heroValue = first.minutes ?? 0;
        heroColor = green;
        caption = 'MINUTES COUNTED';
        body = "You started a workout and didn't finish it in the app. "
            "We trusted you, so today's check-in counts.";
        boxColor = green;
        rows = [
          _InfoRow('Counted for', countedFor(first.date, DateTime.now()), cs.onSurface),
          _InfoRow('Streak', 'Still going', green),
        ];
        tip = "Tip: tap Finish when you're done, so your workout time is exact.";
      case 'own':
        label = 'STREAK ENDED';
        line1 = 'YOU LOST';
        line2 = 'THE STREAK';
        line2Color = c.danger;
        heroKind = NoticeHeroKind.cross;
        heroValue = first.lost;
        caption = 'DAY STREAK WITH ${first.buddy.toUpperCase()}';
        body = "Yesterday's check-in was missed, so your streak with ${first.buddy} ended. "
            'Check in today to start a new one.';
      case 'friend':
        // A shared streak of n days means both of you checked in n times, and
        // a 'friend' event means they were the one who missed yesterday.
        final proven = first.lost > 0;
        label = 'STREAK ENDED';
        line1 = 'YOUR STREAK';
        line2 = 'WITH ${_short(first.buddy)} ENDED';
        line2Color = violet;
        heroKind = NoticeHeroKind.strike;
        heroValue = first.lost;
        heroColor = c.warn;
        caption = 'DAY STREAK';
        body = proven
            ? '${first.missedName} missed yesterday, so your shared streak reset. You did your part.'
            : 'Your shared streak with ${first.buddy} reset yesterday.';
        boxColor = c.warn;
        if (proven) rows = [_InfoRow('Your check-ins', 'All ${first.lost} done', green)];
      default: // many
        label = 'STREAKS ENDED';
        line1 = 'YOU LOST';
        line2 = '${n.items.length} STREAKS';
        line2Color = c.danger;
        body = "Yesterday's check-ins were missed. Here is what ended.";
        list = n.items;
    }

    Widget gap = const SizedBox(height: 14);
    final kids = <Widget>[
      if (heroKind != null) NoticeHero(kind: heroKind, value: heroValue, color: heroColor),
      if (caption != null)
        Text(caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: c.subtleText)),
      Text(body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface)),
      if (rows != null) _InfoBox(color: boxColor, child: Column(children: _divided(rows, boxColor))),
      if (list != null)
        _InfoBox(
          color: boxColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: list.length,
              separatorBuilder: (_, __) => _line(boxColor),
              itemBuilder: (_, i) {
                final it = list![i];
                return _RowIn(
                  index: i,
                  child: _InfoRow(it.buddy, daysLabel(it.lost), it.kind == 'own' ? c.danger : c.warn,
                      labelColor: cs.onSurface),
                );
              },
            ),
          ),
        ),
      if (tip != null)
        Text(tip,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.subtleText, height: 1.4)),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: c.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.cardBorder, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.cardBorder, width: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: _kOrange)),
                    const SizedBox(height: 4),
                    _TitleLine(line1, cs.onSurface),
                    _TitleLine(line2, line2Color),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(children: [
                    for (var i = 0; i < kids.length; i++) ...[if (i > 0) gap, kids[i]],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _dismiss,
                    child: const Text('Got it', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _line(Color c) =>
      Divider(height: 1, thickness: 0.5, color: c.withValues(alpha: 0.28));

  static List<Widget> _divided(List<Widget> rows, Color c) =>
      [for (var i = 0; i < rows.length; i++) ...[if (i > 0) _line(c), rows[i]]];
}

class _TitleLine extends StatelessWidget {
  final String text;
  final Color color;
  const _TitleLine(this.text, this.color);

  // FittedBox: a long buddy name or a huge system font shrinks the line
  // instead of wrapping it into a third line.
  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1.5, height: 0.95, color: color)),
      );
}

class _InfoBox extends StatelessWidget {
  final Color color;
  final Widget child;
  const _InfoBox({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28), width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  final Color? labelColor;
  const _InfoRow(this.label, this.value, this.valueColor, {this.labelColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: labelColor ?? AppColors.of(context).subtleText)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: valueColor)),
          ),
        ]),
      );
}

/// Fades and slides a list row in 0.5 s after the previous one (0.4 s each); only the
/// first five rows animate. Reduce motion: shown at once.
class _RowIn extends StatefulWidget {
  final int index;
  final Widget child;
  const _RowIn({required this.index, required this.child});

  @override
  State<_RowIn> createState() => _RowInState();
}

class _RowInState extends State<_RowIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  Timer? _t;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.index >= 5 || MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else {
      _t = Timer(Duration(milliseconds: 500 * widget.index), _c.forward);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
              .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
          child: widget.child,
        ),
      );
}

// ── NoticeHero: big number with one-shot motion ───────────────────────────

enum NoticeHeroKind { tick, cross, strike }

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// One controller runs 0..1 over [_heroSeconds]; phases are written in seconds.
const _heroSeconds = 3.0;
double _sec(double t, double a, double b) => _seg(t * _heroSeconds, a, b);

class NoticeHero extends StatefulWidget {
  final NoticeHeroKind kind;
  final int value;
  final Color color;
  const NoticeHero({super.key, required this.kind, required this.value, required this.color});

  @override
  State<NoticeHero> createState() => _NoticeHeroState();
}

class _NoticeHeroState extends State<NoticeHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  bool _started = false;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (widget.kind == NoticeHeroKind.tick && !_buzzed && _c.value * _heroSeconds >= 2.6) {
        _buzzed = true;
        HapticFeedback.lightImpact();
      }
    });
  }

  // Once per State: rebuilds and theme changes never restart it.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _buzzed = true;
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.value.toString().length;
    final size = digits <= 2 ? 72.0 : (digits == 3 ? 56.0 : 44.0);
    return SizedBox(
      width: 132,
      height: 132,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double opacity, scale;
          int shown = widget.value;
          if (widget.kind == NoticeHeroKind.tick) {
            shown = (widget.value * Curves.easeOutCubic.transform(_sec(t, 0, 0.8))).round();
            final out = _sec(t, 1.0, 1.3);
            opacity = 1 - out;
            scale = 1 - 0.4 * out;
          } else {
            final u = _sec(t, 0, 0.5);
            scale = 0.6 + 0.4 * Curves.easeOutBack.transform(u);
            opacity = _sec(t, 0, 0.25) *
                (widget.kind == NoticeHeroKind.cross
                    ? 1 - 0.7 * _sec(t, 2.4, 3.0)
                    : 1 - 0.55 * _sec(t, 2.0, 2.6));
          }
          return Stack(alignment: Alignment.center, children: [
            CustomPaint(size: const Size(132, 132), painter: _HeroPainter(widget.kind, t, widget.color)),
            Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: 100,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$shown',
                        style: TextStyle(
                          fontSize: size,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          color: widget.color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  final NoticeHeroKind kind;
  final double t;
  final Color color;
  _HeroPainter(this.kind, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..strokeWidth = kind == NoticeHeroKind.strike ? 8 : 9;
    void line(Offset a, Offset b, double prog) {
      if (prog > 0) canvas.drawLine(a, Offset.lerp(a, b, prog)!, p);
    }

    switch (kind) {
      case NoticeHeroKind.tick:
        final ring = _sec(t, 1.2, 2.0);
        if (ring > 0) {
          canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 5),
              -math.pi / 2, 2 * math.pi * ring, false, p);
        }
        final tick = _sec(t, 1.9, 2.6);
        if (tick > 0) {
          final path = Path()
            ..moveTo(size.width * 0.30, size.height * 0.52)
            ..lineTo(size.width * 0.44, size.height * 0.66)
            ..lineTo(size.width * 0.70, size.height * 0.38);
          final m = path.computeMetrics().first;
          canvas.drawPath(m.extractPath(0, m.length * tick), p);
        }
      case NoticeHeroKind.cross:
        line(const Offset(30, 30), const Offset(102, 102), _sec(t, 1.0, 1.7));
        line(const Offset(102, 30), const Offset(30, 102), _sec(t, 1.7, 2.4));
      case NoticeHeroKind.strike:
        line(const Offset(108, 24), const Offset(24, 108), _sec(t, 1.0, 2.0));
    }
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.t != t || old.color != color || old.kind != kind;
}
