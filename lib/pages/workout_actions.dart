import 'package:flutter/material.dart';

import '../services/handshake_service.dart';
import '../widgets/workout_menu.dart';

/// The four actions that end my part of a workout. Throws if the server refuses.
Future<void> sendEndAction(HandshakeService svc, CardAction a, String id) async {
  switch (a) {
    case CardAction.cantMakeIt: await svc.cantMakeIt(id);
    case CardAction.cancel: await svc.cancel(id);
    default: await svc.leave(id);
  }
}

/// Runs one non-finish action as an RPC and shows the server's error in plain
/// words if it refuses. Returns whether it worked. Change time asks for a date
/// and a time first.
Future<bool> runWorkoutAction(
  BuildContext context,
  HandshakeService svc,
  CardAction a,
  String id, {
  String? otherName,
  required DateTime now,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String t) => messenger.showSnackBar(SnackBar(content: Text(t)));
  try {
    switch (a) {
      case CardAction.imHere: await svc.imHere(id);
      case CardAction.goSolo: await svc.goSolo(id);
      case CardAction.nudge:
        await svc.nudge(id);
        toast('Nudge sent to ${otherName ?? 'your buddy'}.');
      case CardAction.changeTime:
        final local = now.toLocal();
        final date = await showDatePicker(
            context: context, initialDate: local,
            firstDate: DateTime(local.year, local.month, local.day),
            lastDate: local.add(const Duration(days: 60)));
        if (date == null || !context.mounted) return false;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(local));
        if (time == null) return false;
        final t = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
        await svc.changeTime(id, date, t);
        toast('New time sent. ${otherName ?? 'Your buddy'} can accept or decline.');
      case CardAction.finish:
        return false; // finishing has its own flow (finish_flow.dart)
      case CardAction.cantMakeIt || CardAction.cancel || CardAction.leave || CardAction.abandon:
        return false; // these go through the slide sheet (sendEndAction)
    }
    return true;
  } catch (e) {
    toast(HandshakeError.from(e).message(name: otherName));
    return false;
  }
}
