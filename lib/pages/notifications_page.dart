import 'dart:async' show unawaited;

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';

import '../services/coach_max_service.dart';
import '../services/coin_service.dart';
import '../services/notification_inbox_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/run_once.dart';
import '../widgets/ai_disclosure_tag.dart';
import '../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;
import '../widgets/avatars/animated_coach_max.dart';
import '../widgets/user_avatar.dart';
import '../widgets/workout_schedule_card.dart' show ringFromHex;
import 'notification_settings_page.dart';
import 'wardrobe/wardrobe_avatar_render.dart';

// ── Pure helpers ────────────────────────────────────────────────

typedef AskPermission = Future<AuthorizationStatus?> Function();

/// A dot on the bell, and the page's card, only when the permission is known
/// to be off; unknown (not checked yet) shows nothing, so neither flickers on.
bool bellDotVisible(bool? osPermission) => osPermission == false;

/// Android answers at once, without a dialog, when the permission was denied
/// for good; the only way forward is the system settings page. The same rule
/// lives in notification_settings_page.dart (_enableNotifications).
bool dialogWasBlocked(Duration elapsed, AuthorizationStatus? status) =>
    elapsed < const Duration(milliseconds: 400) &&
    status != null &&
    status != AuthorizationStatus.authorized;

/// "Today", "Yesterday", else like "Wed 28 Oct". [day] and [now] are local.
@visibleForTesting
String inboxDayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  if (d == DateTime(now.year, now.month, now.day)) return 'Today';
  if (d == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  return DateFormat('EEE d MMM').format(d);
}

class InboxDayGroup {
  final String label;
  final List<InboxRow> rows;
  InboxDayGroup(this.label, this.rows);
}

/// Rows (already newest first) bucketed by local calendar day, in order.
@visibleForTesting
List<InboxDayGroup> groupInboxByDay(List<InboxRow> rows, DateTime now) {
  final groups = <InboxDayGroup>[];
  DateTime? current;
  for (final row in rows) {
    final l = row.createdAt.toLocal();
    final day = DateTime(l.year, l.month, l.day);
    if (current != day) {
      current = day;
      groups.add(InboxDayGroup(inboxDayLabel(day, now), []));
    }
    groups.last.rows.add(row);
  }
  return groups;
}

/// New since the last visit. No last visit yet means every row is new.
@visibleForTesting
bool inboxRowIsNew(DateTime createdAt, DateTime? lastSeen) =>
    lastSeen == null || createdAt.isAfter(lastSeen);

/// What to store on leaving: the newest row shown, when that moves the marker
/// forward. Null writes nothing, so a failed load clears no dots.
@visibleForTesting
DateTime? nextLastSeen(DateTime? stored, DateTime? newestShown) =>
    newestShown != null && (stored == null || newestShown.isAfter(stored))
    ? newestShown
    : null;

/// The senders to look up: distinct, and never Coach Max, who is drawn here
/// rather than from his profile row.
@visibleForTesting
List<String> inboxSenderIds(List<InboxRow> rows) => {
  for (final row in rows)
    if (row.senderId != null && row.senderId != CoachMaxService.coachMaxId)
      row.senderId!,
}.toList();

/// One sentence for a screen reader, as the mockup reads a row.
@visibleForTesting
String inboxRowSemantics({
  required String title,
  required String body,
  required String time,
  required bool isNew,
  required bool quiet,
}) {
  final words = [title, body].where((s) => s.isNotEmpty).join(' ');
  return '$words, $time${isNew ? ', new' : ''}'
      '${quiet ? '. No sound, quiet hours' : ''}';
}

/// The icon for a row with no sender avatar.
@visibleForTesting
IconData inboxIcon(String type) => switch (type) {
  'friend_request' ||
  'friend_accepted' ||
  'buddy_checked_in' ||
  'buddy_nudge' => Icons.people_outline_rounded,
  'streak_danger' ||
  'streak_broken' ||
  'streak_milestone' ||
  'streak_complete' => Icons.local_fire_department_outlined,
  'coach_max_motivational' || 'coach_max_checked_in' => Icons.smart_toy_outlined,
  'invite_received' ||
  'invite_accepted' ||
  'invite_declined' ||
  'invite_expired' ||
  'invite_rescheduled' ||
  'workout_invite' ||
  'workout_accepted' ||
  'workout_declined' ||
  'workout_cancelled' ||
  'workout_overtime' ||
  'time_to_start' ||
  'buddy_tapped_first' ||
  'started' ||
  'nudge' ||
  'cant_make_it' ||
  'buddy_left' ||
  'buddy_finished' ||
  'still_going' ||
  'before_auto' ||
  'checkin_ready' => Icons.fitness_center_rounded,
  _ => Icons.notifications_none_rounded,
};

// ── Page ────────────────────────────────────────────────────────

/// What the page needs from outside, so tests can hand it fakes.
class NotificationsDeps {
  final Future<List<InboxRow>> Function() loadRows;
  final Future<Map<String, InboxSender>> Function(List<String> ids) loadSenders;
  final Future<Map<String, String>> Function(List<String> ids) loadRings;
  final Future<DateTime?> Function() readLastSeen;
  final Future<void> Function(DateTime value) writeLastSeen;
  final Future<bool> Function(String id) deleteRow;
  final Future<bool> Function() checkPermission;
  final AskPermission askPermission;
  final Future<void> Function() openSystemSettings;
  final Widget Function() settingsPage;

  const NotificationsDeps({
    required this.loadRows,
    required this.loadSenders,
    required this.loadRings,
    required this.readLastSeen,
    required this.writeLastSeen,
    required this.deleteRow,
    required this.checkPermission,
    required this.askPermission,
    required this.openSystemSettings,
    required this.settingsPage,
  });

  factory NotificationsDeps.live() {
    final inbox = NotificationInboxService();
    return NotificationsDeps(
      loadRows: inbox.loadRecent,
      loadSenders: inbox.loadSenders,
      loadRings: (ids) => CoinService().getEquippedColorHexForUsers(ids),
      readLastSeen: inbox.readLastSeen,
      writeLastSeen: inbox.writeLastSeen,
      deleteRow: inbox.deleteRow,
      checkPermission: () => NotificationService().checkOsPermission(),
      askPermission: () => NotificationService().requestPermissionFromUser(),
      openSystemSettings: () =>
          AppSettings.openAppSettings(type: AppSettingsType.notification),
      settingsPage: () => const NotificationSettingsPage(),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  final NotificationsDeps? deps;
  const NotificationsPage({super.key, this.deps});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  late final NotificationsDeps _deps = widget.deps ?? NotificationsDeps.live();
  final _once = RunOnce();
  final _swipedRow = ValueNotifier<String?>(null); // one row open at a time

  List<InboxRow> _rows = [];
  // Deleted or being deleted. The row stays in _rows until a reload, so a failed
  // delete puts it back in its place, and a reload's reply can't bring it back.
  final Set<String> _hidden = {};
  Map<String, InboxSender> _senders = {};
  Map<String, String> _rings = {};
  bool _loading = true;
  bool _failed = false;
  int _gen = 0; // a reply from an older load is dropped

  DateTime? _lastSeenAtOpen; // read once: the dots stay for the whole visit
  DateTime? _stored; // what the device holds now
  DateTime? _newestShown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings: the card goes without leaving the page.
    if (state == AppLifecycleState.resumed) _checkPermission();
    if (state == AppLifecycleState.paused) _saveLastSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveLastSeen();
    _once.dispose();
    _swipedRow.dispose();
    super.dispose();
  }

  List<InboxRow> get _visibleRows =>
      _rows.where((row) => !_hidden.contains(row.id)).toList();

  /// Gone at once. A throw or an empty result (RLS refused it) puts it back.
  /// The last-visit time is left alone: it comes from what was loaded.
  Future<void> _delete(InboxRow row) async {
    if (_hidden.contains(row.id)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (_swipedRow.value == row.id) _swipedRow.value = null;
    setState(() => _hidden.add(row.id));
    var deleted = false;
    try {
      deleted = await _deps.deleteRow(row.id);
    } catch (_) {}
    if (deleted) return;
    if (mounted) setState(() => _hidden.remove(row.id));
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not delete notification')),
    );
  }

  /// A failed check leaves NotificationService.osPermission as it was.
  Future<void> _checkPermission() async {
    try {
      await _deps.checkPermission();
    } catch (_) {}
  }

  Future<void> _start() async {
    try {
      _lastSeenAtOpen = _stored = await _deps.readLastSeen();
    } catch (_) {}
    await _load();
  }

  void _saveLastSeen() {
    final next = nextLastSeen(_stored, _newestShown);
    if (next == null) return;
    _stored = next;
    unawaited(_deps.writeLastSeen(next).catchError((Object _) {}));
  }

  /// Rows, then the avatars for them. A failed avatar lookup still shows the
  /// rows, with default icons.
  Future<void> _load() async {
    final gen = ++_gen;
    try {
      final rows = await _deps.loadRows();
      var senders = <String, InboxSender>{};
      var rings = <String, String>{};
      final ids = inboxSenderIds(rows);
      if (ids.isNotEmpty) {
        try {
          (senders, rings) = await (
            _deps.loadSenders(ids),
            _deps.loadRings(ids),
          ).wait;
        } catch (_) {}
      }
      if (!mounted || gen != _gen) return;
      setState(() {
        _rows = rows;
        _senders = senders;
        _rings = rings;
        _loading = false;
        _failed = false;
      });
      if (rows.isNotEmpty) {
        final newest = rows.first.createdAt;
        if (_newestShown == null || newest.isAfter(_newestShown!)) {
          _newestShown = newest;
        }
      }
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _tryAgain() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _load();
  }

  // One pop only: a double tap would otherwise pop the home screen too.
  void _leave() => _once.latch(() async => Navigator.pop(context));

  /// Pops first: routeTap switches the home tab underneath, which this page
  /// would otherwise hide. A type with no destination stays here.
  void _openRow(InboxRow row) => _once.latch(() async {
    Navigator.pop(context);
    NotificationService.routeTap({
      'type': row.type,
      'reference_id': row.referenceId,
    });
  });

  Future<void> _openSettings() => _once.run(
    () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _deps.settingsPage())),
  );

  Future<void> _turnOn() => _once.run(() async {
    final started = DateTime.now();
    final status = await _deps.askPermission();
    if (dialogWasBlocked(DateTime.now().difference(started), status)) {
      await _deps.openSystemSettings();
    }
  });

  Widget _squareButton({
    required String label,
    required IconData icon,
    required double iconSize,
    required VoidCallback onTap,
    required AppColors c,
    required ColorScheme cs,
  }) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: c.claySurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: iconSize, color: cs.onSurface),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: _squareButton(
              label: 'Back',
              icon: Icons.chevron_left_rounded,
              iconSize: 28,
              onTap: _leave,
              c: c,
              cs: cs,
            ),
          ),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _squareButton(
                label: 'Notification settings',
                icon: Icons.tune_rounded,
                iconSize: 24,
                onTap: _openSettings,
                c: c,
                cs: cs,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: cs.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            ValueListenableBuilder<bool?>(
              valueListenable: NotificationService.osPermission,
              builder: (context, permission, _) => bellDotVisible(permission)
                  ? _offCard(c, cs)
                  : const SizedBox.shrink(),
            ),
            ..._listArea(c, cs),
          ],
        ),
      ),
    );
  }

  Widget _offCard(AppColors c, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.claySurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.streakOrange, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.notifications_off_outlined,
                    size: 28,
                    color: c.streakOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications are off',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Turn them on to get streak alerts and buddy check-ins.',
                        style: TextStyle(color: c.subtleText, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _turnOn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.streakOrange,
                  foregroundColor: c.readableForeground(c.streakOrange),
                  elevation: 0,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Turn on notifications',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle(AppColors c) => TextStyle(
    color: c.subtleText,
    fontSize: 13,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w700,
  );

  BoxDecoration _slab(AppColors c) => BoxDecoration(
    color: c.claySurface,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: c.clayShadowDark,
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  List<Widget> _listArea(AppColors c, ColorScheme cs) {
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(color: cs.primary)),
        ),
      ];
    }
    if (_failed) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Text(
                'Could not load your notifications',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _tryAgain,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    final rows = _visibleRows;
    if (rows.isEmpty) return [_welcomeCard(c, cs)];

    final now = DateTime.now();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Text('LAST 7 DAYS', style: _labelStyle(c)),
      ),
      for (final g in groupInboxByDay(rows, now)) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          // Uppercase on screen only, as Coin history shows it; a screen
          // reader gets the plain words.
          child: Text(
            g.label.toUpperCase(),
            semanticsLabel: g.label,
            style: _labelStyle(c),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: _slab(c),
          child: Column(
            children: [
              for (var i = 0; i < g.rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.divider),
                _SwipeToDelete(
                  key: ValueKey(g.rows[i].id),
                  id: g.rows[i].id,
                  openRow: _swipedRow,
                  onDelete: () => _delete(g.rows[i]),
                  child: _InboxTile(
                    row: g.rows[i],
                    isNew: inboxRowIsNew(g.rows[i].createdAt, _lastSeenAtOpen),
                    sender: _senders[g.rows[i].senderId],
                    ringHex: _rings[g.rows[i].senderId],
                    onTap: tabForType(g.rows[i].type) == null
                        ? null
                        : () => _openRow(g.rows[i]),
                    onDelete: () => _delete(g.rows[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
        child: Text(
          'Older than 7 days is cleared.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.subtleText, fontSize: 13),
        ),
      ),
    ];
  }

  /// Built here only: not a database row, and never written.
  Widget _welcomeCard(AppColors c, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: _slab(c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CoachMaxAvatar(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Coach Max',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const AiInlinePill(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Welcome to your inbox. Check-ins, buddy updates and streak alerts show up here for 7 days.',
                  style: TextStyle(color: c.subtleText, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The still robot on his gradient. The gradient is his badge's own colours
/// (CLAUDE.md), deliberately not an accent token.
class _CoachMaxAvatar extends StatelessWidget {
  final double size;
  final Color? badgeBorder; // null leaves the AI tag off: the name line has it
  const _CoachMaxAvatar({required this.size, this.badgeBorder});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(child: AnimatedCoachMax(size: size, animate: false)),
          ),
          if (badgeBorder != null)
            Positioned(
              bottom: -2,
              right: -6,
              child: AiCornerBadge(scale: 0.85, borderColor: badgeBorder),
            ),
        ],
      ),
    );
  }
}

/// Slides its row left over a red Delete panel. Past half the panel it holds
/// open; all the way across it deletes. A flick only opens it, so a flick can't
/// delete by accident. Tapping the open row closes it. Dismissible can't hold
/// open with a tappable action, so this is written out rather than a new package.
class _SwipeToDelete extends StatefulWidget {
  final String id;
  final ValueNotifier<String?> openRow;
  final VoidCallback onDelete;
  final Widget child;

  const _SwipeToDelete({
    super.key,
    required this.id,
    required this.openRow,
    required this.onDelete,
    required this.child,
  });

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete>
    with SingleTickerProviderStateMixin {
  static const double _panel = 104;
  static const double _deleteAt = 0.6; // share of the row's width

  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 0;

  @override
  void initState() {
    super.initState();
    widget.openRow.addListener(_onOpenRowChanged);
  }

  @override
  void dispose() {
    widget.openRow.removeListener(_onOpenRowChanged);
    _offset.dispose();
    super.dispose();
  }

  void _onOpenRowChanged() {
    if (widget.openRow.value != widget.id) _settle(0);
  }

  void _settle(double target) {
    if (_offset.value == target) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.stop();
      _offset.value = target;
      return;
    }
    _offset.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _close() {
    if (widget.openRow.value == widget.id) widget.openRow.value = null;
    _settle(0);
  }

  void _dragStart(DragStartDetails _) {
    _offset.stop();
    widget.openRow.value = widget.id;
  }

  void _dragUpdate(DragUpdateDetails d) {
    _offset.value = (_offset.value - d.primaryDelta!).clamp(0.0, _width);
  }

  void _dragEnd(DragEndDetails _) {
    if (_offset.value >= _width * _deleteAt) return widget.onDelete();
    if (_offset.value >= _panel / 2) return _settle(_panel);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = c.readableForeground(c.danger);
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        return GestureDetector(
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          child: AnimatedBuilder(
            animation: _offset,
            child: widget.child,
            builder: (context, row) => Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: _offset.value < _panel ? _panel : _offset.value,
                  child: ExcludeSemantics(
                    excluding: _offset.value < _panel,
                    child: Semantics(
                      button: true,
                      label: 'Delete notification',
                      onTap: widget.onDelete,
                      excludeSemantics: true,
                      child: Material(
                        color: c.danger,
                        child: InkWell(
                          onTap: widget.onDelete,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 24,
                                    color: ink,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(-_offset.value, 0),
                  child: Stack(
                    children: [
                      row!,
                      // While open, a tap on the row closes it and never routes.
                      if (_offset.value > 0)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            excludeFromSemantics: true,
                            onTap: _close,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InboxTile extends StatelessWidget {
  static const _deleteAction = CustomSemanticsAction(
    label: 'Delete notification',
  );

  final InboxRow row;
  final bool isNew;
  final InboxSender? sender;
  final String? ringHex;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _InboxTile({
    required this.row,
    required this.isNew,
    required this.sender,
    required this.ringHex,
    required this.onTap,
    required this.onDelete,
  });

  Widget _leading(AppColors c, ColorScheme cs, Color surface) {
    if (row.senderId == CoachMaxService.coachMaxId) {
      return _CoachMaxAvatar(size: 40, badgeBorder: surface);
    }
    final s = sender;
    if (s != null) {
      return WardrobeAvatarRender(
        emoji: UserAvatar.avatars[s.avatarId] ?? UserAvatar.avatars['lion']!,
        avatarId: s.avatarId,
        borderStyle:
            AvatarBorderStyle.values.asNameMap()[s.border] ??
            AvatarBorderStyle.simple,
        borderColor: ringFromHex(ringHex) ?? cs.primary,
        bgColor: c.clayBg,
        size: 40,
        semanticLabel: '',
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.clayBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(inboxIcon(row.type), size: 22, color: cs.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final surface = isNew ? c.claySurfaceLight : c.claySurface;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(row.createdAt.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      customSemanticsActions: {_deleteAction: onDelete},
      excludeSemantics: true,
      label: inboxRowSemantics(
        title: row.title,
        body: row.body,
        time: time,
        isNew: isNew,
        quiet: row.quiet,
      ),
      child: Material(
        color: surface,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              if (isNew)
                Positioned(
                  key: const Key('inbox-new-dot'),
                  left: 5,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.successGreen,
                      ),
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _leading(c, cs, surface),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (row.title.isNotEmpty)
                              Text(
                                row.title,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (row.body.isNotEmpty)
                              Text(
                                row.body,
                                style: TextStyle(
                                  color: c.subtleText,
                                  fontSize: 14,
                                ),
                              ),
                            if (row.quiet) _quietChip(c),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          time,
                          style: TextStyle(
                            color: c.subtleText,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quietChip(AppColors c) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: c.info.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c.info.withValues(alpha: 0.35), width: 0.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.dark_mode_outlined, size: 12, color: c.info),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Quiet hours',
            style: TextStyle(
              color: c.info,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.44,
            ),
          ),
        ),
      ],
    ),
  );
}
