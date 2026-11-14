/// "Today 18:00", "Tomorrow 07:30", "Sat 18:00" (device-local time).
String whenText(DateTime at, DateTime now) {
  final a = at.toLocal(), n = now.toLocal();
  final hm = '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
  final days = DateTime(a.year, a.month, a.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final day = days == 0 ? 'Today' : days == 1 ? 'Tomorrow' : names[a.weekday - 1];
  return '$day $hm';
}

/// "2h 14m", "14m" (rounded up to the minute, at least 1m).
String startsInText(Duration d) {
  final m = (d.inSeconds / 60).ceil().clamp(1, 1 << 30);
  return m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '${m}m';
}

/// "45m", "1h", "1h 30m" for a whole number of minutes.
String formatDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
}
