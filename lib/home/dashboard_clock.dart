import 'dart:math';

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
