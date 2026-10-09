import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Everything a button or menu entry on a workout can ask for.
enum CardAction { imHere, cantMakeIt, nudge, goSolo, cancel, leave, abandon, finish, changeTime }

typedef MenuOption = ({CardAction action, String title, String line});

/// Menu entries for one workout, by role and phase. [running] = the timer has
/// started; [hasBuddy] = someone else is on it.
List<MenuOption> menuOptionsFor({
  required bool iAmCreator,
  required bool running,
  required bool hasBuddy,
  String? otherName,
}) {
  final n = otherName ?? 'your buddy';
  if (!running && iAmCreator) {
    return [
      if (hasBuddy)
        (action: CardAction.changeTime, title: 'Change time',
         line: '$n gets a notification and can accept or decline.'),
      (action: CardAction.cancel, title: 'Cancel workout',
       line: hasBuddy
           ? 'Cancels it for you and $n. $n gets a notification.'
           : 'Cancels this workout.'),
    ];
  }
  if (!running) {
    return [
      (action: CardAction.cantMakeIt, title: "Can't make it",
       line: 'Frees $n up. $n can still work out solo. No penalty.'),
    ];
  }
  if (!hasBuddy) {
    return [
      (action: CardAction.abandon, title: 'Abandon workout',
       line: "Your timer stops and this workout doesn't count."),
    ];
  }
  return [
    (action: CardAction.leave, title: 'Leave workout',
     line: "Your timer stops and this workout doesn't count for you. $n keeps going."),
  ];
}

/// Bottom sheet of bordered boxes plus Keep workout; every option except
/// Change time asks "Are you sure?" first. Returns the confirmed action.
Future<CardAction?> pickWorkoutAction(
  BuildContext context, {
  required String title,
  required List<MenuOption> options,
}) async {
  final c = AppColors.of(context);
  final picked = await showModalBottomSheet<CardAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (final o in options) ...[
            _MenuBox(title: o.title, line: o.line, onTap: () => Navigator.pop(ctx, o.action)),
            const SizedBox(height: 8),
          ],
          _MenuBox(title: 'Keep workout', line: null, color: c.subtleText, onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    ),
  );
  if (picked == null || picked == CardAction.changeTime || !context.mounted) return picked;
  final chosen = options.firstWhere((o) => o.action == picked);
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you sure?'),
      content: Text(chosen.line),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep workout')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(chosen.title)),
      ],
    ),
  );
  return sure == true ? picked : null;
}

class _MenuBox extends StatelessWidget {
  final String title;
  final String? line;
  final Color? color;
  final VoidCallback onTap;
  const _MenuBox({required this.title, required this.line, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: c.cardBorder),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          if (line != null) ...[
            const SizedBox(height: 2),
            Text(line!, style: TextStyle(fontSize: 13, color: c.subtleText)),
          ],
        ]),
      ),
    );
  }
}
