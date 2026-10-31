import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';

void main() {
  test('checkInBannerSubtitle: in says safe, not in says your turn', () {
    final yes = checkInBannerSubtitle(viewerCheckedIn: true);
    final no = checkInBannerSubtitle(viewerCheckedIn: false);
    expect(yes, 'Your streak is safe today');
    expect(no, 'Your turn to check in');
    expect(yes, isNot(no));
  });
}
