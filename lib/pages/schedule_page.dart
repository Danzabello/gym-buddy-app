import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/achievement_service.dart';
import '../services/coin_service.dart';
import '../services/handshake_service.dart';
import '../services/team_streak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/completed_workouts_section.dart';
import '../widgets/schedule_workout_sheet.dart';
import '../widgets/streak_complete_sheet.dart';
import '../widgets/workout_celebration.dart';
import '../widgets/workout_invites_list.dart';
import '../widgets/workout_schedule_card.dart';

/// Workout Schedule tab. The server owns the state: this page fetches
/// get_workout_card, draws it, and turns taps into RPCs.
class SchedulePage extends StatefulWidget {
  final HandshakeService? service;
  const SchedulePage({super.key, this.service});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with WidgetsBindingObserver {
  late final HandshakeService _svc = widget.service ?? HandshakeService();
  final ServerClock _clock = ServerClock();
  WorkoutCardData? _data;
  Person _me = const Person();
  int _streak = 0;
  bool _busy = false;
  bool _fetching = false, _again = false;
  int _completedTrigger = 0;
  final Map<String, Map<String, dynamic>> _overlaps = {};
  PendingFinish? _pending; // complete_workout worked, finish_checkin_session did not
  bool _finishing = false; // quiet 'Finishing your last workout' state
  RealtimeChannel? _channel;
  Timer? _poll;

  String? get _id => _data?.workout?['workout_id'] as String?;
  String? get _name => _data?.workout?['other_person']?['display_name'] as String?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadMe();
    _resumePending();
    // Realtime: any workouts change visible to me -> refetch the card.
    final client = Supabase.instance.client;
    _channel = client
        .channel('workouts', opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'workouts',
            callback: (_) => _refresh())
        .subscribe();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _refresh();
      _resumePending();
    }
  }

  Future<void> _loadMe() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('user_profiles').select('display_name, avatar_id').eq('id', uid).single();
      final hex = (await CoinService().getEquippedColorHexForUsers([uid]))[uid];
      final streaks = await TeamStreakService().getAllUserStreaks();
      if (!mounted) return;
      setState(() {
        _me = Person(
            name: row['display_name'] as String?,
            avatarId: row['avatar_id'] as String?,
            ring: ringFromHex(hex));
        _streak = streaks.fold(0, (m, s) => s.currentStreak > m ? s.currentStreak : m);
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    try {
      final d = await _svc.card();
      _clock.sync(d.serverNow);
      if (mounted) setState(() => _data = d);
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

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Runs one RPC with the tapped buttons disabled; the server answer (the
  /// refetch) decides what the card shows.
  Future<T?> _run<T>(Future<T> Function() call) async {
    setState(() => _busy = true);
    try {
      return await call();
    } catch (e) {
      if (mounted) _toast(HandshakeError.from(e).message(name: _name));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _onAction(CardAction a) async {
    final id = _id;
    if (id == null) return;
    switch (a) {
      case CardAction.imHere: await _run(() => _svc.imHere(id));
      case CardAction.cantMakeIt: await _run(() => _svc.cantMakeIt(id));
      case CardAction.goSolo: await _run(() => _svc.goSolo(id));
      case CardAction.cancel: await _run(() => _svc.cancel(id));
      case CardAction.leave || CardAction.abandon: await _run(() => _svc.leave(id));
      case CardAction.nudge:
        if (await _run(() => _svc.nudge(id)) != null) _toast('Nudge sent to $_name.');
      case CardAction.changeTime: await _changeTime(id);
      case CardAction.finish: await _finish(id);
    }
  }

  Future<void> _changeTime(String id) async {
    final now = _clock.now().toLocal();
    final date = await showDatePicker(
        context: context, initialDate: now,
        firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 60)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null) return;
    final t = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
    if (await _run(() => _svc.changeTime(id, date, t)) != null) {
      _toast('New time sent. ${_name ?? 'Your buddy'} can accept or decline.');
    }
  }

  Future<void> _finish(String id) async {
    final w = _data!.workout!;
    final started = DateTime.parse(w['workout_started_at'] as String);
    final minutes = _clock.now().difference(started).inMinutes;
    await _finishFlow(id, minutes,
        type: w['workout_type'] as String? ?? 'Workout', name: _name);
  }

  /// A finish that was cut short (credit failed, or the app closed): redo
  /// only finish_checkin_session.
  Future<void> _resumePending() async {
    if (_finishing) return;
    final p = await PendingFinish.load();
    if (p == null || !mounted) return;
    setState(() => _pending = p);
    await _finishFlow(p.id, p.minutes, completed: true);
  }

  Future<void> _finishFlow(String id, int minutes,
      {bool completed = false, String type = 'Workout', String? name}) async {
    setState(() {
      _busy = true;
      _finishing = completed;
    });
    try {
      final res = await _svc.finish(id, minutes, alreadyCompleted: completed);
      _pending = null;
      final streaks = TeamStreakService();
      final r = await streaks.applyFinishResult(res);
      if ((r['teams_updated'] as int? ?? 0) > 0) {
        unawaited(AchievementService()
            .checkWorkoutAchievements(durationMinutes: minutes, workoutType: type));
      }
      if (!mounted) return;
      if (!completed) {
        WorkoutCelebration.show(context, workoutType: type, duration: minutes, buddyName: name);
      }
      _completedTrigger++;
      _loadMe();
      if (r['partner_bonus_earned'] == true) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) await StreakCompleteSheet.show(context);
      }
    } on CreditPending {
      _pending = PendingFinish(id, minutes);
      if (mounted) _toast('Workout saved, but your streak credit did not go through.');
    } catch (e) {
      if (mounted) _toast(HandshakeError.from(e).message(name: name));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _finishing = false;
        });
      }
      _refresh();
    }
  }

  Future<void> _accept(String id, {bool force = false}) async {
    final r = await _run(() => _svc.accept(id, force: force));
    if (r == null || !mounted) return;
    setState(() => r['state'] == 'overlap' ? _overlaps[id] = r : _overlaps.remove(id));
  }

  Future<void> _decline(String id) async {
    if (await _run(() => _svc.decline(id)) != null) setState(() => _overlaps.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final received = [
      for (final i in d?.invites ?? const <Map<String, dynamic>>[])
        if (i['direction'] == 'received') i
    ];
    final hasCard = d != null && d.workout != null && d.state != 'none' && d.state != 'closed';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScheduleWorkoutSheet.show(context, onWorkoutScheduled: _refresh),
        icon: const Icon(Icons.add),
        label: const Text('New Workout'),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _refresh();
                setState(() => _completedTrigger++);
              },
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_finishing) _quiet('Finishing your last workout')
                else if (_pending != null) _creditRetry(),
                if (d.openInviteCount >= 3)
                  _quiet('You have ${d.openInviteCount} of 5 invites out'),
                WorkoutInvitesList(
                  invites: received,
                  overlaps: _overlaps,
                  busy: _busy,
                  onAccept: _accept,
                  onDecline: _decline,
                ),
                if (received.isNotEmpty) const SizedBox(height: 16),
                if (hasCard)
                  WorkoutScheduleCard(
                    key: ValueKey(_id),
                    data: d,
                    clock: _clock,
                    me: _me,
                    streakDays: _streak,
                    busy: _busy,
                    onAction: _onAction,
                    onDue: _refresh,
                  )
                else
                  _empty(),
                CompletedWorkoutsSection(refreshTrigger: _completedTrigger),
              ]),
            ),
    );
  }

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
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48), backgroundColor: c.streakOrange),
            onPressed: _busy ? null : () => _finishFlow(_pending!.id, _pending!.minutes, completed: true),
            child: const Text('Retry'),
          ),
        ]),
      ),
    );
  }

  Widget _quiet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.of(context).subtleText)),
      );

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
