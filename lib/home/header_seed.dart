/// The dashboard header's saved copy (cache-first plan, section 3): coins,
/// level, xp and avatar as the server last answered them, so a cold start
/// paints them at once instead of 0 and the default avatar.
library;

import '../services/level_service.dart';
import '../services/saved_copy.dart';
import '../widgets/header_motion.dart';

/// Coins, level and xp are CAREFUL values (owner decision 2026-11-17); the
/// avatar is saved and aged with them.
const kSavedMaxAgeHeader = Duration(days: 7);

/// Saves what the server answered in one load. Null is a read that failed and
/// writes nothing: the numbers only when level and coins both answered, the
/// avatar only when its own read answered ([avatar]'s id is null for an
/// account that never picked one, which is a real answer).
Future<void> saveHeaderAnswers(
  String? uid, {
  LevelInfo? level,
  int? coins,
  ({String? id})? avatar,
  DateTime? now,
}) async {
  if (level != null && coins != null) {
    await SavedCopy.write(uid, 'header', {'level': level.toSaved(), 'coins': coins}, now: now);
  }
  if (avatar != null) {
    await SavedCopy.write(uid, 'avatar', {'avatar_id': avatar.id}, now: now);
  }
}

/// What the header shows after a load: each number the server answered, else
/// the one shown now (the saved copy or an earlier load). Null while one of
/// them has never been known, so a failed read never shows as 0.
({LevelInfo level, int coins})? headerAfterLoad({
  LevelInfo? level,
  int? coins,
  LevelInfo? shownLevel,
  int? shownCoins,
}) {
  final l = level ?? shownLevel;
  final c = coins ?? shownCoins;
  return l == null || c == null ? null : (level: l, coins: c);
}

String? _seedUid;
({String? avatar, bool numbers})? _seed;

/// Before Home builds: puts the saved numbers in [HeaderMotion.session], so
/// the header paints them on its first frame with no entry sweep, and keeps
/// the saved avatar for [claimHeaderSeed]. A session already set is left.
Future<void> seedHeader(String? uid, {DateTime? now}) async {
  if (uid == null) return;
  final numbers = await SavedCopy.read<HeaderRecord>(uid, 'header',
      maxAge: kSavedMaxAgeHeader, now: now, parse: (d) {
    final m = d as Map<String, dynamic>;
    return HeaderRecord(
        LevelInfo.fromSaved(Map<String, dynamic>.from(m['level'] as Map)), m['coins'] as int);
  });
  final avatar = await SavedCopy.read<String?>(uid, 'avatar',
      maxAge: kSavedMaxAgeHeader, now: now, parse: (d) => (d as Map)['avatar_id'] as String?);
  final seeded = numbers != null && HeaderMotion.session == null;
  if (seeded) HeaderMotion.session = numbers;
  _seedUid = uid;
  _seed = (avatar: avatar, numbers: seeded);
}

/// Taken once by the dashboard before it builds its header motion. A seed
/// read for another user is dropped, numbers included, so another account's
/// header is never shown. Null when no seed is waiting for [uid].
({String? avatar, bool numbers})? claimHeaderSeed(String? uid) {
  final owner = _seedUid;
  final seed = _seed;
  _seedUid = null;
  _seed = null;
  if (owner == null || seed == null) return null;
  if (owner != uid) {
    if (seed.numbers) HeaderMotion.session = null;
    return null;
  }
  return seed;
}

/// The first answer after a saved seed: any lower number (coins, level, or xp
/// in the same level) snaps rather than counting down from the saved one.
/// Higher still counts up, equal does nothing (HeaderMotion.sync), and every
/// other mode is kept.
HeaderSyncMode seededSyncMode(
  HeaderSyncMode mode, {
  required LevelInfo shown,
  required int shownCoins,
  required LevelInfo level,
  required int coins,
}) {
  if (mode != HeaderSyncMode.animate) return mode;
  final lower = coins < shownCoins ||
      level.level < shown.level ||
      (level.level == shown.level && level.xpIntoCurrentLevel < shown.xpIntoCurrentLevel);
  return lower ? HeaderSyncMode.snap : mode;
}

/// Whether the first-answer rule has done its job: numbers the server
/// answered ([answered]) were applied (not held) or were already what the
/// header shows ([matches]). Kept saved numbers from a failed load never end
/// it, and an equal answer that arrived under a hold does.
bool seedSettled({
  required bool answered,
  required HeaderSyncMode mode,
  required bool matches,
}) =>
    answered && (mode != HeaderSyncMode.hold || matches);
