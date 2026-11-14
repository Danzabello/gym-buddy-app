import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/data/avatar_catalog.dart';
import 'package:gym_buddy_app/home_screen.dart';
import 'package:gym_buddy_app/widgets/user_avatar.dart';

// Pins the pure profile helpers and the avatar emoji data as they were before
// the client refactor (refactor/client-2026-11), so a move cannot change them.
void main() {
  group('formatYear', () {
    test('year of an ISO timestamp', () {
      expect(formatYear('2024-03-09T10:11:12.000Z'), '2024');
      expect(formatYear('2026-11-14'), '2026');
    });
    test('null and unparsable fall back to 2025', () {
      expect(formatYear(null), '2025');
      expect(formatYear(''), '2025');
      expect(formatYear('not a date'), '2025');
    });
  });

  group('levelGradient', () {
    const bands = <int, List<Color>>{
      1: [Color(0xFFFFB300), Color(0xFFFF8F00)],
      11: [Color(0xFF378ADD), Color(0xFF185FA5)],
      26: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
      46: [Color(0xFFEF9F27), Color(0xFFBA7517)],
      56: [Color(0xFFD4537E), Color(0xFF993556)],
      76: [Color(0xFFD85A30), Color(0xFF993C1D)],
      91: [Color(0xFF7F77DD), Color(0xFF534AB7)],
    };
    final starts = bands.keys.toList();
    for (var i = 0; i < starts.length; i++) {
      final lo = starts[i];
      final hi = i + 1 < starts.length ? starts[i + 1] - 1 : 100;
      test('levels $lo to $hi', () {
        expect(levelGradient(lo), bands[lo]);
        expect(levelGradient(hi), bands[lo]);
      });
    }
    test('below 1 and above 100 use the end bands', () {
      expect(levelGradient(0), bands[1]);
      expect(levelGradient(-5), bands[1]);
      expect(levelGradient(500), bands[91]);
    });
  });

  group('titleIcon', () {
    const icons = {
      'Newcomer': '🌱', 'Beginner': '⚡', 'Rookie': '🔥',
      'Athlete': '💪', 'Warrior': '⚔️', 'Iron': '🛡️',
      'Beast': '🦁', 'Legend': '👑', 'Elite': '💎',
      'Champion': '🏆', 'Gym Pro': '🌟',
    };
    icons.forEach((title, icon) {
      test(title, () => expect(titleIcon(title), icon));
    });
    test('unknown title gets the star', () {
      expect(titleIcon('Nobody'), '⭐');
      expect(titleIcon(''), '⭐');
      expect(titleIcon('newcomer'), '⭐');
    });
  });

  group('avatar emoji data', () {
    const expected = {
      'lion': '🦁',
      'bear': '🐻',
      'eagle': '🦅',
      'shark': '🦈',
      'wolf': '🐺',
      'gorilla': '🦍',
      'tiger': '🐯',
      'buffalo': '🦬',
      'robot': '🤖',
      'flexed': '💪',
      'weightlifter': '🏋️',
      'runner': '🏃',
    };

    test('UserAvatar.avatars has the twelve ids and their emoji', () {
      expect(UserAvatar.avatars, expected);
    });

    test('the catalogue lists the same ids with the same emoji', () {
      expect({for (final e in avatarCatalog) e.id: e.emoji}, expected);
    });

    testWidgets('an unknown or missing id shows the lion', (tester) async {
      // 'zebra' has no illustration, so the emoji fallback is what renders.
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: UserAvatar(avatarId: 'zebra'),
      ));
      expect(find.text('🦁'), findsOneWidget);
    });
  });
}
