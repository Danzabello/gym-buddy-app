import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/notice_screens.dart';

Map<String, dynamic> ev(String id, String kind, int lost, {String? buddy, bool coach = false, String? best}) => {
      'id': id, 'kind': kind, 'lost_streak': lost, 'buddy_name': buddy,
      'is_coach_max_team': coach, 'team_name': 'Team', 'missed_name': 'Sam',
      if (best != null) 'best_streak': int.parse(best),
    };

void main() {
  test('null kind or empty items -> no notice', () {
    expect(Notice.parse({'kind': null, 'items': [], 'others': 0}), isNull);
    expect(Notice.parse(null), isNull);
  });

  test('own: best missing is null, present is parsed; ids and others kept', () {
    final n = Notice.parse({'kind': 'own', 'others': 2, 'items': [ev('a', 'own', 12, buddy: 'Sam')]})!;
    expect(n.kind, 'own');
    expect(n.others, 2);
    expect(n.ids, ['a']);
    expect(n.items.first.best, isNull);
    final b = Notice.parse({'kind': 'own', 'items': [ev('a', 'own', 12, buddy: 'Sam', best: '20')]})!;
    expect(b.items.first.best, 20);
  });

  test('coach max team name, long name kept whole', () {
    final n = Notice.parse({'kind': 'many', 'items': [
      ev('a', 'own', 3, coach: true),
      ev('b', 'friend', 1, buddy: 'A' * 80),
    ]})!;
    expect(n.items[0].buddy, 'Coach Max');
    expect(n.items[1].buddy.length, 80);
    expect(n.items[1].kind, 'friend');
  });

  test('auto_completed items parse as auto', () {
    final n = Notice.parse({'kind': 'auto_completed', 'others': 0, 'items': [
      {'id': 'x', 'workout_date': '2026-10-06', 'minutes': 15}
    ]})!;
    expect(n.items.first.kind, 'auto');
    expect(n.items.first.minutes, 15);
  });

  test('day pluralisation and counted-for', () {
    expect(daysLabel(1), '1 day');
    expect(daysLabel(2), '2 days');
    final now = DateTime(2026, 10, 7);
    expect(countedFor('2026-10-07', now), 'Today');
    expect(countedFor('2026-10-06', now), 'Tuesday');
    expect(countedFor(null, now), 'Today');
  });
}
