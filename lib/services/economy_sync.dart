import 'package:flutter/foundation.dart';
import 'package:gym_buddy_app/services/coin_service.dart';
import 'package:gym_buddy_app/services/level_service.dart';

/// Coins and level/xp as the server last reported them.
class EconomyNumbers {
  const EconomyNumbers(this.level, this.coins);
  final LevelInfo? level;
  final int coins;
}

/// Keeps the dashboard header equal to the server after a credit lands.
/// Whatever pays coins or xp (Finish, an achievement, a synced invite bonus,
/// a shop purchase) calls [refresh]; [numbers] changes once the server
/// answers, and the dashboard listens to it.
class EconomySync {
  EconomySync({Future<EconomyNumbers?> Function()? fetch}) : _fetch = fetch ?? _live;

  static final EconomySync instance = EconomySync();

  /// Latest server numbers; null until the first refresh.
  final ValueNotifier<EconomyNumbers?> numbers = ValueNotifier(null);

  final Future<EconomyNumbers?> Function() _fetch;
  bool _busy = false;
  bool _again = false;

  /// Re-reads the numbers through get_my_profile. Calls that arrive while a
  /// read is in flight collapse into one more read, so the last value shown
  /// always comes from a read that started after the last credit.
  Future<void> refresh() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final n = await _fetch();
        if (n != null) numbers.value = n;
      } while (_again);
    } catch (e) {
      if (kDebugMode) debugPrint('EconomySync.refresh: $e');
    } finally {
      _busy = false;
    }
  }

  // A failed level read returns null; keep what is on screen rather than zero it.
  static Future<EconomyNumbers?> _live() async {
    final level = await LevelService().getLevelInfo();
    if (level == null) return null;
    return EconomyNumbers(level, await CoinService().getBalance());
  }
}
