import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/achievement_service.dart';
import 'package:gym_buddy_app/widgets/achievement_toast.dart';
import 'package:gym_buddy_app/widgets/header_motion.dart';

AchievementUnlockResult result(String id) => AchievementUnlockResult(
      achievement: Achievement(
        id: id,
        name: 'Name $id',
        description: 'd',
        category: 'c',
        icon: 'x',
        rarity: 'rare',
        xpReward: 10,
        coinReward: 5,
        targetValue: 1,
        sortOrder: 1,
      ),
      xpAwarded: 10,
      coinsAwarded: 5,
    );

void main() {
  tearDown(() => expect(HeaderHold.instance.active, isFalse,
      reason: 'a test left a hold behind'));

  Future<BuildContext> host(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    return ctx;
  }

  testWidgets('a toast holds the header while it is up and lets go after', (t) async {
    final ctx = await host(t);
    expect(HeaderHold.instance.active, isFalse);
    AchievementToast.show(ctx, [result('a')]);
    await t.pump();
    expect(find.text('Name a'), findsOneWidget);
    expect(HeaderHold.instance.active, isTrue);
    await t.pump(const Duration(milliseconds: 3400));
    expect(HeaderHold.instance.active, isTrue);
    await t.pump(const Duration(milliseconds: 150)); // timer fires, slide out starts
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(find.text('Name a'), findsNothing);
    expect(HeaderHold.instance.active, isFalse);
  });

  testWidgets('several toasts each take their own hold', (t) async {
    final ctx = await host(t);
    AchievementToast.show(ctx, [result('a'), result('b')]);
    await t.pump();
    expect(HeaderHold.instance.active, isTrue);
    await t.pump(const Duration(milliseconds: 3600));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(find.textContaining('Name'), findsNothing);
    expect(HeaderHold.instance.active, isFalse);
  });

  testWidgets('tapping a toast dismisses it and lets go', (t) async {
    final ctx = await host(t);
    AchievementToast.show(ctx, [result('a')]);
    await t.pump(); // builds the entry and starts the slide-in
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Name a'));
    await t.pump();
    expect(find.text('Name a'), findsNothing);
    expect(HeaderHold.instance.active, isFalse);
    await t.pump(const Duration(seconds: 4)); // the auto timer finds it unmounted
  });
}
