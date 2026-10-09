import 'dart:async';

import 'package:flutter/material.dart';

import '../services/handshake_service.dart';
import '../theme/app_theme.dart';
import '../utils/workout_time.dart';
import '../widgets/workout_menu.dart';
import '../widgets/workout_schedule_card.dart';
import 'finish_flow.dart';
import 'schedule_deps.dart';
import 'workout_actions.dart';

/// One workout: header, then the ring card. Driven by get_workout_card(id).
/// Nothing here ever pushes or re-opens a page: leaving is always the back arrow.
class WorkoutPage extends StatefulWidget {
  final String workoutId;
  final ScheduleDeps? deps;
  const WorkoutPage({super.key, required this.workoutId, this.deps});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> with WidgetsBindingObserver {
  late final ScheduleDeps _deps = widget.deps ?? ScheduleDeps.live();
  final ServerClock _clock = ServerClock();
  WorkoutCardData? _data;
  bool _gone = false; // closed, deleted, or not mine
  Person _me = const Person();
  int _streak = 0;
  bool _busy = false;
  bool _fetching = false, _again = false;
  late final Unsubscribe _unlisten;
  Timer? _poll;

  Map<String, dynamic> get _w => _data?.workout ?? const {};
  String? get _name => (_w['other_person'] as Map?)?['display_name'] as String?;
  String get _type => _w['workout_type'] as String? ?? 'Workout';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _deps.loadMe().then((p) => mounted ? setState(() => _me = p) : null).catchError((_) {});
    _deps.loadStreak().then((n) => mounted ? setState(() => _streak = n) : null).catchError((_) {});
    _unlisten = _deps.listen(_refresh);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _unlisten();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    try {
      final d = await _deps.svc.card(widget.workoutId);
      _clock.sync(d.serverNow);
      if (mounted) setState(() { _data = d; _gone = d.state == 'closed'; });
    } on HandshakeError catch (e) {
      if (mounted && (e.code == 'not_found' || e.code == 'not_participant')) setState(() => _gone = true);
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

  Future<void> _onAction(CardAction a) async {
    setState(() => _busy = true);
    try {
      if (a == CardAction.finish) {
        final started = DateTime.parse(_w['workout_started_at'] as String);
        final minutes = _clock.now().difference(started).inMinutes;
        final r = await finishWorkout(context, _deps.svc,
            id: widget.workoutId, minutes: minutes, type: _type, name: _name);
        if (r != FinishResult.failed && mounted) Navigator.of(context).maybePop();
        return;
      }
      final ok = await runWorkoutAction(context, _deps.svc, a, widget.workoutId,
          otherName: _name, now: _clock.now());
      const leaving = {CardAction.cancel, CardAction.leave, CardAction.abandon, CardAction.cantMakeIt};
      if (ok && leaving.contains(a) && mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _openMenu() async {
    final a = await pickWorkoutAction(context,
        title: _name == null ? _type : '$_type with $_name',
        options: menuOptionsFor(
            iAmCreator: _w['i_am_creator'] == true,
            running: isRunningState(_data!.state),
            hasBuddy: _w['other_person'] != null,
            otherName: _name));
    if (a != null && mounted) _onAction(a);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = _data;
    final planned = d == null || _w['planned_at'] == null ? null : DateTime.parse(_w['planned_at'] as String);
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Workout' : (_name == null ? _type : '$_type with $_name'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (d != null && !_gone)
            IconButton(
              tooltip: 'Workout options',
              icon: const Icon(Icons.more_vert),
              onPressed: _busy ? null : _openMenu,
            ),
        ],
      ),
      body: _gone
          ? Center(child: Text('This workout is over.', style: TextStyle(color: c.subtleText)))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (planned != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(whenText(planned, _clock.now()), style: TextStyle(color: c.subtleText)),
                    ),
                  WorkoutScheduleCard(
                    data: d,
                    clock: _clock,
                    me: _me,
                    streakDays: _streak,
                    busy: _busy,
                    showHeader: false,
                    onAction: _onAction,
                    onDue: _refresh,
                  ),
                ]),
    );
  }
}
