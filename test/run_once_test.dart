import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/utils/run_once.dart';

void main() {
  group('RunOnce', () {
    test('a second call while the first is pending is ignored', () async {
      final once = RunOnce();
      final gate = Completer<void>();
      var runs = 0;
      final first = once.run(() async { runs++; await gate.future; return 'a'; });
      expect(once.isRunning, isTrue);
      expect(await once.run(() async { runs++; return 'b'; }), isNull);
      gate.complete();
      expect(await first, 'a');
      expect(runs, 1);
    });

    test('a call after completion runs', () async {
      final once = RunOnce();
      var runs = 0;
      await once.run(() async => runs++);
      expect(once.isRunning, isFalse);
      await once.run(() async => runs++);
      expect(runs, 2);
    });

    test('the guard is released when the action throws, and the error propagates', () async {
      final once = RunOnce();
      await expectLater(once.run<void>(() async => throw StateError('boom')), throwsStateError);
      expect(once.isRunning, isFalse);
      await expectLater(once.run<void>(() => throw StateError('sync')), throwsStateError);
      expect(once.isRunning, isFalse);
      expect(await once.run(() async => 7), 7);
    });

    test('nothing runs after dispose', () async {
      final once = RunOnce()..dispose();
      var runs = 0;
      expect(await once.run(() async => runs++), isNull);
      expect(runs, 0);
    });

    test('held until a pushed route future completes', () async {
      final once = RunOnce();
      final popped = Completer<void>();
      var pushes = 0;
      unawaited(once.run(() { pushes++; return popped.future; }));
      await once.run(() { pushes++; return popped.future; });
      expect(pushes, 1);
      popped.complete();
      await Future<void>.delayed(Duration.zero);
      await once.run(() async => pushes++);
      expect(pushes, 2);
    });
  });
}
