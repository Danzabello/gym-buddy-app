import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/dashboard_refresh.dart';

void main() {
  final now = DateTime(2026, 11, 17, 12);
  DateTime ago(int seconds) => now.subtract(Duration(seconds: seconds));

  test('never loaded or stale: always refresh', () {
    expect(shouldRefresh(lastLoaded: null, now: now, dirty: false), isTrue);
    expect(shouldRefresh(lastLoaded: null, now: now, dirty: false, resumed: ago(1)), isTrue);
  });

  test('tab return: only when dirty and older than 2 minutes', () {
    expect(shouldRefresh(lastLoaded: ago(121), now: now, dirty: true), isTrue);
    expect(shouldRefresh(lastLoaded: ago(120), now: now, dirty: true), isFalse);
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: false), isFalse);
    expect(shouldRefresh(lastLoaded: ago(5), now: now, dirty: true), isFalse);
  });

  test('resume: only after more than 5 minutes in the background', () {
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: false, resumed: ago(301)), isTrue);
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: true, resumed: ago(300)), isFalse);
    // Old data but a short trip to another app: no refresh.
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: false, resumed: ago(10)), isFalse);
  });

  test('fresh and clean: no refresh', () {
    expect(shouldRefresh(lastLoaded: ago(1), now: now, dirty: false), isFalse);
  });
}
