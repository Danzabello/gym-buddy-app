import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/duration_picker.dart';

// The "Set Duration" sheet and the two-tier duration colour that the schedule
// sheets share.
void main() {
  final colors = AppColors.fromAccent(AccentPalette.emeraldInk);

  Future<List<int>> open(WidgetTester t, {required int initial}) async {
    final chosen = <int>[];
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [colors]),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showCustomDurationDialog(ctx,
                initial: initial, onSet: chosen.add),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return chosen;
  }

  testWidgets('durationColor is neutral up to 30 minutes, accent above',
      (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [colors]),
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    expect(durationColor(ctx, null), colors.subtleText);
    expect(durationColor(ctx, 0), colors.subtleText);
    expect(durationColor(ctx, 30), colors.subtleText);
    expect(durationColor(ctx, 31), colors.streakOrange);
    expect(durationColor(ctx, 180), colors.streakOrange);
  });

  testWidgets('the sheet opens on the initial duration with six quick picks',
      (t) async {
    final chosen = await open(t, initial: 60);
    expect(find.text('Set Duration'), findsNWidgets(2)); // title and button
    // The dial and the 1h chip both read "1h".
    expect(find.text('1h'), findsNWidgets(2));
    for (final label in ['15m', '30m', '45m', '1h 30m', '2h']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('3 hours'), findsOneWidget);
    expect(chosen, isEmpty);
  });

  testWidgets('a quick pick then the button reports it once and closes',
      (t) async {
    final chosen = await open(t, initial: 60);
    await t.tap(find.text('45m'));
    await t.pumpAndSettle();
    expect(find.text('45m'), findsNWidgets(2)); // dial and chip
    expect(chosen, isEmpty); // nothing is reported until the button
    await t.tap(find.widgetWithText(ElevatedButton, 'Set Duration'));
    await t.pumpAndSettle();
    expect(chosen, [45]);
    expect(find.text('Set Duration'), findsNothing);
  });

  testWidgets('dismissing the sheet reports nothing', (t) async {
    final chosen = await open(t, initial: 90);
    await t.tapAt(const Offset(10, 10)); // the barrier above the sheet
    await t.pumpAndSettle();
    expect(find.text('Set Duration'), findsNothing);
    expect(chosen, isEmpty);
  });
}
