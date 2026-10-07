import 'package:flutter/material.dart';
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
      final nav = appNavigatorKey.currentState;
      if (nav == null) return;
      _others.value = 0;
      await nav.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => NoticeScreen(notice),
      ));
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
        final p = context.watch<AccentThemeProvider>().palette;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Material(
            color: p.cardBackground,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _check,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      n == 1 ? 'You have 1 more update' : 'You have $n more updates',
                      style: TextStyle(color: p.subtleText, fontSize: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: p.subtleText),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Screens ───────────────────────────────────────────────────────────────

class NoticeScreen extends StatelessWidget {
  final Notice notice;
  const NoticeScreen(this.notice, {super.key});

  Future<void> _dismiss(BuildContext context) async {
    final nav = Navigator.of(context);
    try {
      await Supabase.instance.client
          .rpc('mark_notice_seen', params: {'p_ids': notice.ids});
    } catch (_) {
      // Server keeps it pending; it shows again on the next open.
    }
    if (nav.mounted && nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AccentThemeProvider>().palette;
    final first = notice.items.first;
    final n = notice.items.length;
    final Widget art;
    final String title, body, primary;
    final List<(String, String, Color?)> rows;
    String? tip;
    var showClose = true;
    List<NoticeItem>? list;

    switch (notice.kind) {
      case 'auto_completed':
        art = _Ring(color: p.statusSuccess, child: Icon(Icons.check, size: 48, color: p.statusSuccess));
        title = 'We completed your check-in';
        body = "You started a workout and didn't finish it in the app. "
            "We trusted you, so today's check-in counts.";
        rows = [
          if (first.minutes != null) ('Workout goal', '${first.minutes} min', null),
          ('Counted for', countedFor(first.date, DateTime.now()), null),
          ('Streak', 'Still going', p.statusSuccess),
        ];
        primary = 'Got it';
        tip = "Tip: tap Finish when you're done, so your workout time is exact.";
        showClose = false;
      case 'own':
        art = _Ring(color: p.statusDanger, child: Icon(Icons.close, size: 48, color: p.statusDanger));
        title = 'You lost the streak';
        body = "Your streak with ${first.buddy} ended because yesterday's check-in was missed.";
        rows = [
          ('Streak that ended', daysLabel(first.lost), p.statusDanger),
          if (first.best != null) ('Your best', '${daysLabel(first.best!)}, kept', null),
        ];
        primary = 'Start a new streak';
      case 'friend':
        // A shared streak of n days means both of you checked in n times, and
        // a 'friend' event means they were the one who missed yesterday.
        final proven = first.lost > 0;
        art = _BrokenPair(me: _myInitial(), buddy: first.missedName, color: p.statusWarning);
        title = 'Your streak with ${first.buddy} ended';
        body = proven
            ? '${first.missedName} missed yesterday, so your shared streak reset. You did your part.'
            : 'Your shared streak with ${first.buddy} reset yesterday.';
        rows = [
          ('Streak that ended', daysLabel(first.lost), p.statusWarning),
          if (proven) ('Your check-ins', 'All ${first.lost} done', p.statusSuccess),
        ];
        primary = 'Restart with ${first.buddy}';
      default: // many
        art = _Ring(color: p.statusDanger, child: Text('$n', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: p.statusDanger)));
        title = 'You lost $n streaks';
        body = "Yesterday's check-ins were missed. Here's what ended.";
        rows = const [];
        list = notice.items;
        primary = 'Start fresh today';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss(context);
      },
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 56, 28, 36),
            child: Column(children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          art,
                          const SizedBox(height: 28),
                          Text(title,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.primaryText)),
                          const SizedBox(height: 12),
                          Text(body,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, height: 1.4, color: p.subtleText)),
                          const SizedBox(height: 24),
                          _Card(
                            color: p.cardBackground,
                            child: list != null
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: list.length,
                                      separatorBuilder: (_, __) => Divider(height: 1, color: p.divider),
                                      itemBuilder: (_, i) => _ManyRow(list![i], p),
                                    ),
                                  )
                                : Column(children: [
                                    for (var i = 0; i < rows.length; i++) ...[
                                      if (i > 0) Divider(height: 1, color: p.divider),
                                      _Row(rows[i].$1, rows[i].$2, rows[i].$3 ?? p.primaryText, p.subtleText),
                                    ],
                                  ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.action,
                    foregroundColor: AppColors.of(context).readableForeground(p.action),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _dismiss(context),
                  child: Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              if (tip != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(tip, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p.subtleText)),
                ),
              if (showClose)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => _dismiss(context),
                    child: Text('Close', style: TextStyle(fontSize: 16, color: p.subtleText)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  static String _myInitial() {
    final u = Supabase.instance.client.auth.currentUser;
    final meta = u?.userMetadata;
    final s = (meta?['display_name'] ?? meta?['username'] ?? u?.email ?? '') as String;
    return s.trim().isEmpty ? 'Y' : s.trim();
  }
}

class _Ring extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Ring({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: 112,
        height: 112,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 6)),
        child: child,
      );
}

class _BrokenPair extends StatelessWidget {
  final String me, buddy;
  final Color color;
  const _BrokenPair({required this.me, required this.buddy, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AccentThemeProvider>().palette;
    Widget av(String name, {bool dim = false}) => Opacity(
          opacity: dim ? 0.55 : 1,
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.cardBackground,
              border: Border.all(color: dim ? color : p.divider, width: 3),
            ),
            child: Text(name.characters.first.toUpperCase(),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.primaryText)),
          ),
        );
    Widget dash() => Container(width: 14, height: 3, color: color);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      av(me),
      const SizedBox(width: 8),
      dash(),
      const SizedBox(width: 10),
      dash(),
      const SizedBox(width: 8),
      av(buddy, dim: true),
    ]);
  }
}

class _Card extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Card({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _Row extends StatelessWidget {
  final String label, value;
  final Color valueColor, labelColor;
  const _Row(this.label, this.value, this.valueColor, this.labelColor);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 16, color: labelColor))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: valueColor)),
          ),
        ]),
      );
}

class _ManyRow extends StatelessWidget {
  final NoticeItem item;
  final AccentPalette p;
  const _ManyRow(this.item, this.p);

  @override
  Widget build(BuildContext context) {
    final own = item.kind == 'own';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.buddy, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.primaryText)),
            Text(own ? 'You missed a check-in' : '${item.missedName} missed a check-in',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: p.subtleText)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(daysLabel(item.lost),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: own ? p.statusDanger : p.statusWarning)),
      ]),
    );
  }
}
