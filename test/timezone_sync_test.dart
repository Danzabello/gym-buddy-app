import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/utils/timezone_sync.dart';

Future<List<String>> _run({String? stored, Future<String> Function()? zone}) async {
  final writes = <String>[];
  await syncDeviceTimezone(
    stored: stored,
    userId: 'u1',
    deviceZone: zone ?? () async => 'Europe/Paris',
    write: (id, iana) async => writes.add('$id:$iana'),
  );
  return writes;
}

void main() {
  test('same zone as stored writes nothing', () async {
    expect(await _run(stored: 'Europe/Paris'), isEmpty);
  });

  test('different zone writes once', () async {
    expect(await _run(stored: 'Europe/Dublin'), ['u1:Europe/Paris']);
  });

  test('unknown stored value writes', () async {
    expect(await _run(), ['u1:Europe/Paris']);
  });

  test('device zone unreadable writes nothing', () async {
    expect(await _run(zone: () async => throw Exception('no tz')), isEmpty);
  });

  test('a failing write is swallowed', () async {
    await syncDeviceTimezone(
      userId: 'u1',
      deviceZone: () async => 'Europe/Paris',
      write: (_, __) async => throw Exception('offline'),
    );
  });
}
