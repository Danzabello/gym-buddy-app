import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/finish_flow.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/widgets/header_motion.dart';

class _Svc extends HandshakeService {
  _Svc(this.onFinish);
  final Future<Map<String, dynamic>> Function() onFinish;
  @override
  Future<Map<String, dynamic>> finish(String id, int minutes,
          {bool alreadyCompleted = false}) =>
      onFinish();
}

void main() {
  bool held() => HeaderHold.instance.active;

  tearDown(() => expect(held(), isFalse, reason: 'a test left a hold behind'));

  Future<FinishResult> run(
    WidgetTester t,
    _Svc svc,
    FinishHooks hooks,
  ) async {
    late FinishResult r;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async =>
                r = await finishWorkout(c, svc, id: 'w', minutes: 30, hooks: hooks),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump();
    return r;
  }

  FinishHooks hooks(List<String> log) => FinishHooks(
        apply: (_) async => {'teams_updated': 1, 'partner_bonus_earned': true},
        achievements: (_, __) {},
        celebrate: (_, __, ___, ____) async => log.add('celebrate held=${held()}'),
        streakSheet: (_) async => log.add('sheet held=${held()}'),
      );

  testWidgets('held from the first await through celebration and streak sheet', (t) async {
    final log = <String>[];
    final svc = _Svc(() async {
      log.add('finish held=${held()}');
      return {'result': 'ok'};
    });
    final r = await run(t, svc, hooks(log));
    expect(r, FinishResult.done);
    expect(log, ['finish held=true', 'celebrate held=true', 'sheet held=true']);
    expect(held(), isFalse);
  });

  testWidgets('released when the server credited nothing', (t) async {
    final log = <String>[];
    final svc = _Svc(() async {
      log.add('finish held=${held()}');
      return {'result': 'nothing_to_finish'};
    });
    final r = await run(t, svc, hooks(log));
    expect(r, FinishResult.done);
    expect(log, ['finish held=true']);
    expect(held(), isFalse);
  });

  testWidgets('released when the credit is pending', (t) async {
    final svc = _Svc(() async => throw const CreditPending(HandshakeError('x')));
    final r = await run(t, svc, hooks([]));
    expect(r, FinishResult.creditPending);
    expect(held(), isFalse);
  });

  testWidgets('released when the finish fails', (t) async {
    final svc = _Svc(() async => throw Exception('boom'));
    final r = await run(t, svc, hooks([]));
    expect(r, FinishResult.failed);
    expect(held(), isFalse);
  });

  testWidgets('released when a hook throws', (t) async {
    final svc = _Svc(() async => {'result': 'ok'});
    final bad = FinishHooks(
      apply: (_) async => throw Exception('apply'),
      achievements: (_, __) {},
      celebrate: (_, __, ___, ____) async {},
      streakSheet: (_) async {},
    );
    final r = await run(t, svc, bad);
    expect(r, FinishResult.failed);
    expect(held(), isFalse);
  });
}
