import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/notification_settings_page.dart';

const _static = 'Turn every kind on or off at once';

void main() {
  test('permission off: drawn off with the static subtitle for every count', () {
    for (var count = 0; count <= 4; count++) {
      expect(masterSwitchOn(permissionGranted: false, count: count), isFalse,
          reason: 'count $count');
      expect(masterSubtitle(permissionGranted: false, count: count), _static,
          reason: 'count $count');
    }
  });

  test('permission on: count 4, 2 and 0', () {
    expect(masterSwitchOn(permissionGranted: true, count: 4), isTrue);
    expect(masterSubtitle(permissionGranted: true, count: 4), 'All 4 kinds on');
    expect(masterSwitchOn(permissionGranted: true, count: 2), isTrue);
    expect(masterSubtitle(permissionGranted: true, count: 2), '2 of 4 kinds on');
    expect(masterSwitchOn(permissionGranted: true, count: 0), isFalse);
    expect(masterSubtitle(permissionGranted: true, count: 0), 'All kinds off');
  });

  test('a tap sets all off for 4 and 2, all on for 0', () {
    expect(nextKindValue(4), isFalse);
    expect(nextKindValue(2), isFalse);
    expect(nextKindValue(0), isTrue);
  });
}
