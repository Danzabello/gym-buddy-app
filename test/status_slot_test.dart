import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';

// Card 1 has one slot and three variants. The danger window is what decides
// which of them owns it — including for "secured", which is the resolved half
// of the countdown rather than an all-day badge.
void main() {
  test('danger window shows the streak status', () {
    expect(
      resolveStatusSlot(
          hasBuddy: true, buddyCheckedIn: false, inDangerWindow: true),
      StatusSlot.danger,
    );
    expect(
      resolveStatusSlot(
          hasBuddy: true, buddyCheckedIn: true, inDangerWindow: true),
      StatusSlot.secured,
    );
  });

  test('outside the window the feed always owns the slot', () {
    expect(
      resolveStatusSlot(
          hasBuddy: true, buddyCheckedIn: false, inDangerWindow: false),
      StatusSlot.feed,
    );
    // The regression this fixes: "secured" used to win here all day, so the
    // feed never surfaced once a buddy had checked in.
    expect(
      resolveStatusSlot(
          hasBuddy: true, buddyCheckedIn: true, inDangerWindow: false),
      StatusSlot.feed,
    );
  });

  test('no buddy to wait on never reaches a status variant', () {
    expect(
      resolveStatusSlot(
          hasBuddy: false, buddyCheckedIn: false, inDangerWindow: true),
      StatusSlot.feed,
    );
    expect(
      resolveStatusSlot(
          hasBuddy: false, buddyCheckedIn: false, inDangerWindow: false),
      StatusSlot.feed,
    );
  });
}
