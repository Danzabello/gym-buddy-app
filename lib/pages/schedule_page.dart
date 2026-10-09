import 'dart:async';

import 'package:flutter/material.dart';

import '../services/handshake_service.dart';
import '../theme/app_theme.dart';
import '../widgets/schedule_rows.dart';
import '../widgets/schedule_workout_sheet.dart';
import '../widgets/workout_invites_list.dart';
import '../widgets/workout_menu.dart';
import '../widgets/workout_schedule_card.dart';
import 'finish_flow.dart';
import 'schedule_deps.dart';
import 'workout_actions.dart';
import 'workout_page.dart';

/// Workout Schedule: the list. A Now row, Upcoming rows, Invitations, recent
/// completed. Each workout opens on its own page.
class SchedulePage extends StatefulWidget {
  final ScheduleDeps? deps;
  const SchedulePage({super.key, this.deps});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with WidgetsBindingObserver {
  late final ScheduleDeps _deps = widget.deps ?? ScheduleDeps.live();
  final ServerClock _clock = ServerClock();
  WorkoutCardData? _head; // get_workout_card(): invites + counts + server time
  List<Map<String, dynamic>> _rows = []; // one card per open workout
  Person _me = const Person();
  bool _loaded = false;
  bool _fetching = false, _again = false;
  bool _finishing = false;
  PendingFinish? _pending;
  int _completedTrigger = 0;
  final Map<String, Map<String, dynamic>> _overlaps = {};
  late final Unsubscribe _unlisten;
  Timer? _poll, _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _deps.loadMe().then((p) => mounted ? setState(() => _me = p) : null).catchError((_) {});
    _resumePending();
    _unlisten = _deps.listen(_refresh);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _refresh();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _rows.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tick?.cancel();
    _unlisten();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _refresh();
      _resumePending();
    }
  }

  Future<void> _refresh() async {
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
    } catch (_) {
      // keep what is on screen; the next event or the 30 s poll retries
    } finally {
      _fetching = false;
      if (_again && mounted) {
        _again = false;
        _refresh();
      }
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutPage(workoutId: id, deps: widget.deps)));
    if (mounted) {
      _refresh();
      setState(() => _completedTrigger++);
    }
  }

  Future<void> _rowMenu(Map<String, dynamic> w) async {
    final name = (w['other_person'] as Map?)?['display_name'] as String?;
    final a = await pickWorkoutAction(context,
        title: name == null ? w['workout_type'] as String : '${w['workout_type']} with $name',
        options: menuOptionsFor(
            iAmCreator: w['i_am_creator'] == true,
            running: false,
            hasBuddy: w['other_person'] != null,
            otherName: name));
    if (a == null || !mounted) return;
    await runWorkoutAction(context, _deps.svc, a, w['workout_id'] as String,
        otherName: name, now: _clock.now());
    _refresh();
  }

  Future<void> _answer(String id, {required bool accept, bool force = false}) async {
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
    final head = _head;
    final received = [
      for (final i in head?.invites ?? const <Map<String, dynamic>>[])
        if (i['direction'] == 'received') i
    ];
    final now = _clock.now();
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
    final c = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScheduleWorkoutSheet.show(context, onWorkoutScheduled: _refresh),
        icon: const Icon(Icons.add),
        label: const Text('New Workout'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _refresh();
                setState(() => _completedTrigger++);
              },
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_finishing)
                  _quiet('Finishing your last workout')
                else if (_pending != null)
                  _creditRetry(),
                if (nowRow != null) ...[
                  NowRow(
                    workout: nowRow, me: _me, now: now,
                    onTap: () => _open(nowRow['workout_id'] as String)),
                  const SizedBox(height: 16),
                ],
                if (upcoming.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('Upcoming', style: TextStyle(fontWeight: FontWeight.bold, color: c.subtleText)),
                  ),
                  for (final w in upcoming)
                    UpcomingRow(
                      workout: w, me: _me, now: now,
                      onTap: () => _open(w['workout_id'] as String),
                      onMenu: () => _rowMenu(w)),
                  const SizedBox(height: 8),
                ],
                if (outCount >= 3) _quiet('You have $outCount of 5 invites out'),
                WorkoutInvitesList(
                  invites: received,
                  overlaps: _overlaps,
                  onAccept: (id, {force = false}) => _answer(id, accept: true, force: force),
                  onDecline: (id) => _answer(id, accept: false),
                ),
                if (received.isNotEmpty) const SizedBox(height: 16),
                if (nowRow == null && upcoming.isEmpty && received.isEmpty) _empty(),
                _deps.completed(_completedTrigger),
              ]),
            ),
    );
  }

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
          Text('Tap + to schedule a workout', style: TextStyle(fontSize: 14, color: c.subtleText)),
        ]),
      ),
    );
  }
}
