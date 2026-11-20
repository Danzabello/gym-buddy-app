import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';

// Time here is the test binding's fake clock (the same FakeAsync fakeAsync
// uses): tester.pump(duration) moves it and fires the due timers. A timer that
// is left running when a test ends fails that test ("A Timer is still
// pending"), so every test also proves it leaves no timer behind.
void main() {
  const tick = Duration(seconds: 2);

  // The dashboard's flag, mounted state and screen, as plain variables.
  late int shown;
  late bool handled;
  late bool mounted;
  late bool free;
  late WeeklyPlanWaiter waiter;

  setUp(() {
    shown = 0;
    handled = false;
    mounted = true;
    free = false;
    waiter = WeeklyPlanWaiter(
      isMounted: () => mounted,
      alreadyHandled: () => handled,
      screenFree: () => free,
      // What the dashboard's show does: the flag first, synchronously, then the dialog.
      show: () {
        handled = true;
        shown++;
      },
    );
  });

  testWidgets('later, then the screen becomes free: the dialog is shown once and the timer is gone', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    expect(waiter.waiting, isTrue);
    await t.pump(tick * 3); // three ticks with the screen busy
    expect(shown, 0);

    free = true;
    await t.pump(tick);
    expect(shown, 1);
    expect(waiter.waiting, isFalse);

    await t.pump(const Duration(seconds: 30));
    expect(shown, 1); // nothing again
  });

  testWidgets('later, and the screen stays busy: nothing is shown after many ticks', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    await t.pump(const Duration(minutes: 5));
    expect(shown, 0);
    expect(waiter.waiting, isTrue); // still waiting
    waiter.cancel(); // the test's own clean-up: a pending timer would fail it
  });

  testWidgets('dispose while waiting: the timer is cancelled and nothing happens afterwards', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    await t.pump(tick * 2);
    waiter.cancel(); // what the dashboard's dispose does
    expect(waiter.waiting, isFalse);

    free = true;
    await t.pump(const Duration(minutes: 1));
    expect(shown, 0);
  });

  testWidgets('a State that is gone without having cancelled stops the timer on its next tick', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    mounted = false;
    free = true;
    await t.pump(tick);
    expect(shown, 0);
    expect(waiter.waiting, isFalse);
  });

  testWidgets('more checks that say later while waiting start no second timer and show nothing twice', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);

    free = true;
    await t.pump(tick);
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter); // a late answer after it was shown
    await t.pump(const Duration(seconds: 10));
    expect(shown, 1);
    // A second timer, replaced by the extra starts, would still be pending
    // here and would fail this test when it ends.
    waiter.cancel();
  });

  testWidgets('a check that finds the screen free while waiting shows once and cancels the waiter', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);

    free = true;
    applyWeeklyPlanStep(WeeklyPlanStep.show, waiter); // a fresh check before the tick
    expect(shown, 1);
    expect(waiter.waiting, isFalse);

    await t.pump(const Duration(seconds: 30)); // the old tick must not show it again
    expect(shown, 1);
  });

  testWidgets('a fresh check that says skip (a plan exists now) cancels the waiter and nothing is shown', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    await t.pump(tick * 2);
    expect(waiter.waiting, isTrue);

    applyWeeklyPlanStep(WeeklyPlanStep.skip, waiter);
    expect(waiter.waiting, isFalse);

    free = true;
    await t.pump(const Duration(minutes: 1));
    expect(shown, 0);
  });

  testWidgets('the flag set elsewhere stops the waiter without showing', (t) async {
    applyWeeklyPlanStep(WeeklyPlanStep.later, waiter);
    handled = true; // another dashboard instance showed it
    free = true;
    await t.pump(tick);
    expect(shown, 0);
    expect(waiter.waiting, isFalse);
  });

  testWidgets('start is idempotent: the waiter waits once however many times it is started', (t) async {
    expect(waiter.waiting, isFalse);
    waiter.start();
    waiter.start();
    expect(waiter.waiting, isTrue);
    waiter.cancel();
    expect(waiter.waiting, isFalse);
    waiter.cancel(); // cancelling twice is fine
  });
}
