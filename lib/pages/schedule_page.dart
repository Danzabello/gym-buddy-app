import 'dart:async';

import 'package:flutter/material.dart';

import '../services/handshake_service.dart';
import '../services/saved_copy.dart';
import '../services/tab_refresh.dart';
import '../theme/app_theme.dart';
import '../widgets/schedule_rows.dart';
import '../widgets/schedule_workout_sheet.dart';
import '../widgets/tab_keep_alive.dart';
import '../widgets/workout_invites_list.dart';
import '../widgets/workout_menu.dart';
import '../widgets/workout_schedule_card.dart';
import 'finish_flow.dart';
import 'schedule_deps.dart';
import 'workout_actions.dart';
import 'workout_page.dart';
import '../utils/run_once.dart';

/// Workout Schedule: the list. A Now row, Upcoming rows, Invitations, recent
/// completed. Each workout opens on its own page.
class SchedulePage extends StatefulWidget {
  final ScheduleDeps? deps;
  final ServerClock? clock; // tests move time with it
  const SchedulePage({super.key, this.deps, this.clock});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage>
    with AutomaticKeepAliveClientMixin, TabKeepAlive {
  @override
  AppTab get tab => AppTab.schedule;
  late final ScheduleDeps _deps = widget.deps ?? ScheduleDeps.live();
  late final ServerClock _clock = widget.clock ?? ServerClock();
  WorkoutCardData? _head; // get_workout_card(): invites + counts + server time
  List<Map<String, dynamic>> _rows = []; // one card per open workout
  Person _me = const Person();
  bool _loaded = false;
  bool _fetching = false, _again = false;
  bool _finishing = false;
  final _once = RunOnce();
  final _answerOnce = RunOnce();
  PendingFinish? _pending;
  int _completedTrigger = 0;
  final Map<String, Map<String, dynamic>> _overlaps = {};
  late final Unsubscribe _unlisten;
  Timer? _poll, _tick;
  // Ticks once a second; only the rows listen, so the page itself is not rebuilt.
  final ValueNotifier<int> _secondTick = ValueNotifier(0);

  static const _pollEvery = Duration(seconds: 30);

  /// Ends when the first refresh does (loaded or failed). While the page
  /// shows the saved copy, a tap on a row or an invite waits for it, at most
  /// about 3 s, then acts: the server decides either way.
  final _firstRefresh = Completer<void>();

  @override
  void initState() {
    super.initState();
    _restoreSaved();
    _refresh();
    _loadMe();
    _unlisten = _deps.listen(_onWorkoutsChanged);
    // A tab built while a nav tap crosses it stays quiet until it is shown.
    if (tabShown) {
      _resumePending();
      _startClocks();
    }
  }

  @override
  void dispose() {
    _stopClocks();
    _secondTick.dispose();
    _unlisten();
    _once.dispose();
    _answerOnce.dispose();
    super.dispose();
  }

  /// First paint from the saved copy (same local day, at most 12 h old): the
  /// list and the invites, without syncing the clock from its old server
  /// time. A load that finished first wins.
  Future<void> _restoreSaved() async {
    final saved = await SavedCopy.read<(WorkoutCardData, List<Map<String, dynamic>>)>(
      SavedCopy.uid,
      'schedule',
      maxAge: kSavedMaxAgeSchedule,
      sameDay: true,
      parse: (d) {
        final m = d as Map<String, dynamic>;
        return (
          WorkoutCardData.fromJson(Map<String, dynamic>.from(m['head'] as Map)),
          [for (final r in m['rows'] as List) Map<String, dynamic>.from(r as Map)],
        );
      },
    );
    if (saved == null || !mounted || _loaded || _firstRefresh.isCompleted) return;
    setState(() {
      _head = saved.$1;
      _rows = saved.$2;
      _loaded = true;
    });
  }

  void _loadMe() =>
      _deps.loadMe().then((p) => mounted ? setState(() => _me = p) : null).catchError((_) {});

  /// The 30 s poll and the 1 s tick run only while the tab shows.
  void _startClocks() {
    _poll ??= Timer.periodic(_pollEvery, (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _refresh();
    });
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _rows.isNotEmpty) _secondTick.value++;
    });
  }

  void _stopClocks() {
    _poll?.cancel();
    _tick?.cancel();
    _poll = _tick = null;
  }

  /// A workouts Realtime event: refetch now when shown, else on the next show.
  void _onWorkoutsChanged() => tabShown ? _refresh() : markStale({AppTab.schedule});

  @override
  void onTabShown() => _startClocks();

  @override
  void onTabHidden() => _stopClocks();

  /// Settled on screen, or the app resumed while it shows: redo a finish
  /// that was cut short, and run the poll tick missed while hidden (a
  /// workout's state moves with time, not only with row changes). A stale
  /// tab skips it: refreshInBackground runs right after.
  @override
  void onTabSettled() {
    _resumePending();
    final last = refreshState.lastLoaded;
    if (!refreshState.stale && last != null && DateTime.now().difference(last) >= _pollEvery) {
      _refresh();
    }
  }

  /// A write made elsewhere (a finish, a workout action, an equip or avatar
  /// change), an event while hidden, a long trip away or a new day.
  @override
  void refreshInBackground() {
    _refresh();
    _loadMe();
    setState(() => _completedTrigger++);
  }

  Future<void> _refresh() => refreshState.track(() async {
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    try {
      final ids = await _deps.listIds();
      final results = await Future.wait<WorkoutCardData?>([
        _deps.svc.card(),
        for (final id in ids) _deps.svc.card(id).then<WorkoutCardData?>((d) => d).catchError((_) => null),
      ]);
      final head = results.first!;
      _clock.sync(head.serverNow);
      // A row whose card failed is missing here: such a list is not saved.
      final whole = results.every((d) => d != null);
      final rows = [
        for (final d in results.skip(1))
          if (d != null && d.workout != null && d.state != 'closed') d.workout!
      ];
      if (mounted) {
        setState(() {
          _head = head;
          _rows = rows;
          _loaded = true;
        });
      }
      if (whole) {
        unawaited(SavedCopy.write(SavedCopy.uid, 'schedule', {
          'head': head.toSaved(),
          'rows': rows,
        }, zone: profileZone));
      }
    } catch (_) {
      // keep what is on screen; the next event, the 30 s poll or the next
      // show retries
      refreshState.failed();
    } finally {
      _fetching = false;
      if (!_firstRefresh.isCompleted) _firstRefresh.complete();
      if (_again && mounted) {
        _again = false;
        _refresh();
      }
    }
  });

  void _toast(String text) => showTabSnackBar(SnackBar(content: Text(text)));

  /// A finish that was cut short (credit failed, or the app closed): redo only
  /// finish_checkin_session.
  Future<void> _resumePending() async {
    if (_finishing) return;
    final p = await PendingFinish.load();
    if (p == null || !mounted) return;
    setState(() {
      _pending = p;
      _finishing = true;
    });
    final r = await finishWorkout(context, _deps.svc, id: p.id, minutes: p.minutes, completed: true, hooks: _deps.finishHooks);
    if (!mounted) return;
    setState(() {
      _finishing = false;
      if (r != FinishResult.creditPending) _pending = null;
      if (r == FinishResult.done) _completedTrigger++;
    });
    _refresh();
  }

  Future<void> _open(String id) async {
    await awaitConfirmed(_firstRefresh.future); // saved copy: wait for the refresh
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutPage(workoutId: id, deps: widget.deps)));
    if (mounted) {
      _refresh();
      setState(() => _completedTrigger++);
    }
  }

  Future<void> _rowMenu(Map<String, dynamic> tapped) async {
    await awaitConfirmed(_firstRefresh.future); // saved copy: wait for the refresh
    if (!mounted) return;
    final w = _rows.firstWhere((r) => r['workout_id'] == tapped['workout_id'], orElse: () => tapped);
    final name = (w['other_person'] as Map?)?['display_name'] as String?;
    final a = await pickWorkoutAction(context,
        title: name == null ? w['workout_type'] as String : '${w['workout_type']} with $name',
        options: menuOptionsFor(
            iAmCreator: w['i_am_creator'] == true,
            running: false,
            hasBuddy: w['other_person'] != null,
            otherName: name),
        me: _me,
        buddy: w['other_person'] == null ? null : otherPerson(w),
        run: (a) => sendEndAction(_deps.svc, a, w['workout_id'] as String));
    if (a == CardAction.changeTime && mounted) {
      await runWorkoutAction(context, _deps.svc, CardAction.changeTime, w['workout_id'] as String,
          otherName: name, now: _clock.now());
    }
    if (a != null) _refresh();
  }

  Future<void> _answer(String id, {required bool accept, bool force = false}) async {
    await awaitConfirmed(_firstRefresh.future); // saved copy: wait for the refresh
    if (!mounted) return;
    try {
      final r = accept ? await _deps.svc.accept(id, force: force) : await _deps.svc.decline(id);
      if (!mounted) return;
      setState(() => accept && r['state'] == 'overlap' ? _overlaps[id] = r : _overlaps.remove(id));
    } catch (e) {
      if (mounted) _toast(HandshakeError.from(e).message());
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    final head = _head;
    final received = [
      for (final i in head?.invites ?? const <Map<String, dynamic>>[])
        if (i['direction'] == 'received') i
    ];
    // Now: the first workout that is happening (running first, else earliest).
    final happening = [for (final w in _rows) if (nowStates.contains(w['state'])) w]
      ..sort((a, b) {
        final ar = isRunningState(a['state'] as String) ? 0 : 1, br = isRunningState(b['state'] as String) ? 0 : 1;
        return ar != br ? ar - br : (a['planned_at'] as String).compareTo(b['planned_at'] as String);
      });
    final nowRow = happening.isEmpty ? null : happening.first;
    final upcoming = [for (final w in _rows) if (w != nowRow) w]
      ..sort((a, b) => (a['planned_at'] as String).compareTo(b['planned_at'] as String));
    final outCount = head?.openInviteCount ?? 0;
    final isEmpty = nowRow == null && upcoming.isEmpty && received.isEmpty;
    final c = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _refresh();
                setState(() => _completedTrigger++);
              },
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (!isEmpty) ...[_newWorkoutButton(), const SizedBox(height: 16)],
                if (_finishing)
                  _quiet('Finishing your last workout')
                else if (_pending != null)
                  _creditRetry(),
                if (nowRow != null) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _secondTick,
                    builder: (_, _, _) => NowRow(
                      workout: nowRow, me: _me, now: _clock.now(),
                      onTap: () => _once.run(() => _open(nowRow['workout_id'] as String)))),
                  const SizedBox(height: 16),
                ],
                if (upcoming.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('Upcoming', style: TextStyle(fontWeight: FontWeight.bold, color: c.subtleText)),
                  ),
                  for (final w in upcoming)
                    ValueListenableBuilder<int>(
                      valueListenable: _secondTick,
                      builder: (_, _, _) => UpcomingRow(
                        workout: w, me: _me, now: _clock.now(),
                        onTap: () => _once.run(() => _open(w['workout_id'] as String)),
                        onMenu: () => _once.run(() => _rowMenu(w)))),
                  const SizedBox(height: 8),
                ],
                if (outCount >= 3) _quiet('You have $outCount of 5 invites out'),
                WorkoutInvitesList(
                  invites: received,
                  overlaps: _overlaps,
                  onAccept: (id, {force = false}) => _answerOnce.run(() => _answer(id, accept: true, force: force)),
                  onDecline: (id) => _answerOnce.run(() => _answer(id, accept: false)),
                ),
                if (received.isNotEmpty) const SizedBox(height: 16),
                if (isEmpty) _empty(),
                _deps.completed(_completedTrigger),
              ]),
            ),
    );
  }

  /// Always reachable: top of the list, or inside the empty state.
  Widget _newWorkoutButton() => FilledButton(
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.of(context).streakOrange),
        onPressed: () => _once.run(() => ScheduleWorkoutSheet.show(context, onWorkoutScheduled: _refresh)),
        child: const Text('New workout'),
      );

  Widget _quiet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.of(context).subtleText)),
      );

  Widget _creditRetry() {
    final c = AppColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Workout saved. Your streak credit did not go through.',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: c.streakOrange),
            onPressed: _resumePending,
            child: const Text('Retry'),
          ),
        ]),
      ),
    );
  }

  Widget _empty() {
    final c = AppColors.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.calendar_today, size: 64, color: c.subtleText),
          const SizedBox(height: 16),
          Text('No scheduled workouts',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text('Schedule one with a buddy or on your own.', style: TextStyle(fontSize: 14, color: c.subtleText)),
          const SizedBox(height: 16),
          _newWorkoutButton(),
        ]),
      ),
    );
  }
}
