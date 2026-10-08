import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushPayload.fromData', () {
    test('reads every field of a full data message', () {
      final p = PushPayload.fromData({
        'title': 'Sam',
        'body': 'is here. Your move.',
        'type': 'buddy_tapped_first',
        'reference_id': 'w1',
        'kind': 'orange',
        'color': '#EA580C',
        'channel': 'gym_buddy_handshake',
        'tag': 'hs_w1',
        'avatar_id': 'bear',
        'avatar_border': 'bold',
        'ring_hex': '#3FC1C9',
        'sender_name': 'Sam',
        'streak': '5',
      })!;
      expect(
          [p.title, p.body, p.type, p.referenceId, p.kind, p.color, p.channel, p.tag],
          ['Sam', 'is here. Your move.', 'buddy_tapped_first', 'w1', 'orange', '#EA580C',
           'gym_buddy_handshake', 'hs_w1']);
      expect([p.avatarId, p.avatarBorder, p.ringHex, p.senderName, p.streak],
          ['bear', 'bold', '#3FC1C9', 'Sam', '5']);
      expect(p.hasSender, isTrue);
    });

    test('missing fields become empty strings', () {
      final p = PushPayload.fromData({'title': 'Streak ended'})!;
      expect([p.body, p.type, p.kind, p.channel, p.tag, p.avatarId], everyElement(''));
      expect(p.hasSender, isFalse);
    });

    test('no title means nothing to show', () {
      expect(PushPayload.fromData({}), isNull);
      expect(PushPayload.fromData({'type': 'nudge', 'body': 'x'}), isNull);
    });
  });

  group('kind → colour', () {
    const want = {
      'orange': Color(0xFFEA580C),
      'lavender': Color(0xFFA99BF5),
      'emerald': Color(0xFF50C878),
      'amber': Color(0xFFFBBF24),
      'red': Color(0xFFF87171),
      'grey': Color(0xFFB9CFC3),
    };
    for (final e in want.entries) {
      test(e.key, () {
        expect(colorForPush(PushPayload(title: 't', body: 'b', kind: e.key)), e.value);
      });
    }
    test('explicit color wins over kind', () {
      expect(colorForPush(const PushPayload(title: 't', body: 'b', kind: 'red', color: '#123456')),
          const Color(0xFF123456));
    });
    test('unknown kind and bad color fall back to grey', () {
      expect(colorForPush(const PushPayload(title: 't', body: 'b', kind: 'pink', color: 'blue')),
          const Color(0xFFB9CFC3));
    });
  });

  group('channels', () {
    test('the five new channels exist and the legacy one is kept', () {
      expect(kPushChannels.map((c) => c.id), containsAll([
        'gym_buddy_high_importance', 'gym_buddy_handshake', 'gym_buddy_invites',
        'gym_buddy_streaks', 'gym_buddy_friends', 'gym_buddy_coach_max',
      ]));
    });
    test('handshake buzzes twice, streaks once long and silent', () {
      expect(channelFor('gym_buddy_handshake').vibrationPattern, [0, 150, 120, 150]);
      final streaks = channelFor('gym_buddy_streaks');
      expect(streaks.vibrationPattern, [0, 700]);
      expect(streaks.playSound, isFalse);
    });
    test('unknown or missing channel → legacy channel', () {
      expect(channelFor('gym_buddy_nope').id, 'gym_buddy_high_importance');
      expect(channelFor(null).id, 'gym_buddy_high_importance');
    });
  });

  group('tap routing', () {
    test('handshake and invite types open the Workout Schedule tab', () {
      for (final t in ['invite_received', 'invite_accepted', 'time_to_start', 'nudge',
                       'started', 'buddy_left', 'still_going', 'before_auto']) {
        expect(tabForType(t), 0, reason: t);
      }
    });
    test('friend types open Friends, streak types the Dashboard', () {
      expect(tabForType('friend_request'), 1);
      expect(tabForType('friend_accepted'), 1);
      for (final t in ['buddy_checked_in', 'streak_milestone', 'streak_broken',
                       'streak_danger', 'buddy_nudge', 'coach_max_motivational']) {
        expect(tabForType(t), 2, reason: t);
      }
    });
    test('unknown type does nothing', () {
      expect(tabForType('something_else'), isNull);
      expect(tabForType(null), isNull);
    });
  });

  group('renderAvatarPng', () {
    bool isPng(List<int> b) =>
        b.length > 100 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

    test('bear (painter)', () async {
      expect(isPng(await renderAvatarPng('bear', 'simple', '#3FC1C9', useCache: false)), isTrue);
    });
    test('emoji avatar', () async {
      expect(isPng(await renderAvatarPng('wolf', 'bold', null, useCache: false)), isTrue);
    });
    test('missing avatar id', () async {
      expect(isPng(await renderAvatarPng(null, null, null, useCache: false)), isTrue);
    });
    test('ring defaults to emerald when none equipped', () {
      expect(parseHexColor(null) ?? kDefaultRingColor, const Color(0xFF50C878));
      expect(parseHexColor('') ?? kDefaultRingColor, const Color(0xFF50C878));
      expect(parseHexColor('#FF6F5E'), const Color(0xFFFF6F5E));
    });
  });
}
