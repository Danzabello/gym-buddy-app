import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';

// The only non-trivial maths behind the "next milestone" card: which target a
// streak is working toward and how full the bar is between the last one and it.
void main() {
  test('targets the next milestone above the current streak', () {
    expect(getNextMilestone(0)?.target, 1);
    expect(getNextMilestone(1)?.target, 3);
    expect(getNextMilestone(7)?.target, 14);
    expect(getNextMilestone(7)?.name, 'Two Weeks');
    expect(getNextMilestone(7)?.toGo, 7);
  });

  test('progress spans previous milestone to next', () {
    expect(getNextMilestone(7)?.progress, 0.0);           // just hit 7
    expect(getNextMilestone(10)?.progress, closeTo(3 / 7, 1e-9));
    expect(getNextMilestone(13)?.progress, closeTo(6 / 7, 1e-9));
    expect(getNextMilestone(0)?.progress, 0.0);           // no previous yet
  });

  test('runs out once every milestone is behind', () {
    expect(getNextMilestone(365), isNull);
    expect(getNextMilestone(400), isNull);
  });
}
