import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/wardrobe/wardrobe_selection_state.dart';
import 'package:gym_buddy_app/services/coin_service.dart';
import 'package:gym_buddy_app/services/level_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:gym_buddy_app/widgets/avatar_picker_screen.dart' show AvatarBorderStyle;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

ShopItem _ring(String id, {bool owned = true, bool equipped = false}) => ShopItem(
      id: id,
      name: '$id Ring',
      description: '',
      category: 'ring_color',
      cost: 10,
      emoji: '⭕',
      assetId: '',
      isOwned: owned,
      isEquipped: equipped,
      unlockLevel: 1,
      colorHex: '#FF0000',
    );

({String? avatarId, AvatarBorderStyle border}) _profile(String? id, AvatarBorderStyle b) =>
    (avatarId: id, border: b);

/// Survives a real save and read: JSON text and back.
Map<String, dynamic> _viaJson(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  final shownProfile = _profile('wolf', AvatarBorderStyle.bold);
  final shownRings = [_ring('red', equipped: true), _ring('blue')];
  final shownUnlocks = <Map<String, dynamic>>[
    {'shop_item_id': 'bold', 'unlock_reason': 'level_3'},
  ];
  final WardrobeParts shown =
      (profile: shownProfile, ringItems: shownRings, unlocks: shownUnlocks, level: 7);
  const WardrobeParts failed = noWardrobeParts;

  group('wardrobeAfterLoad', () {
    test('a load where every read failed keeps everything shown', () {
      expect(wardrobeAfterLoad(shown, failed), shown);
    });

    final fresh = <String, WardrobeParts>{
      'profile': (profile: _profile('lion', AvatarBorderStyle.simple), ringItems: null, unlocks: null, level: null),
      'ringItems': (profile: null, ringItems: [_ring('new')], unlocks: null, level: null),
      'unlocks': (profile: null, ringItems: null, unlocks: [], level: null),
      'level': (profile: null, ringItems: null, unlocks: null, level: 8),
    };
    for (final part in fresh.keys) {
      test('only $part answered: it updates and the other three keep their shown value', () {
        final next = wardrobeAfterLoad(shown, fresh[part]!);
        expect(identical(next.profile, shown.profile), part != 'profile');
        expect(identical(next.ringItems, shown.ringItems), part != 'ringItems');
        expect(identical(next.unlocks, shown.unlocks), part != 'unlocks');
        expect(next.level == shown.level, part != 'level');
      });
    }

    test('an empty list of unlocks is a real answer and replaces the shown one', () {
      final next = wardrobeAfterLoad(shown, (profile: null, ringItems: null, unlocks: [], level: null));
      expect(next.unlocks, isEmpty);
    });
  });

  group('wardrobeReady and wardrobeSavedPayload', () {
    test('nothing shown and every read failed paints nothing: no grid, no Default ring, no locks, no level 1', () {
      final next = wardrobeAfterLoad(noWardrobeParts, failed);
      expect(wardrobeReady(next), isFalse);
      expect(next, noWardrobeParts);
    });

    test('every part is needed', () {
      expect(wardrobeReady(shown), isTrue);
      expect(wardrobeReady((profile: null, ringItems: shownRings, unlocks: shownUnlocks, level: 7)), isFalse);
      expect(wardrobeReady((profile: shownProfile, ringItems: null, unlocks: shownUnlocks, level: 7)), isFalse);
      expect(wardrobeReady((profile: shownProfile, ringItems: shownRings, unlocks: null, level: 7)), isFalse);
      expect(wardrobeReady((profile: shownProfile, ringItems: shownRings, unlocks: shownUnlocks, level: null)), isFalse);
    });

    test('a complete answer is saved, a partial one never is', () {
      expect(wardrobeSavedPayload(shown), isNotNull);
      expect(wardrobeSavedPayload((profile: shownProfile, ringItems: shownRings, unlocks: shownUnlocks, level: null)), isNull);
      expect(wardrobeSavedPayload((profile: shownProfile, ringItems: null, unlocks: shownUnlocks, level: 7)), isNull);
      expect(wardrobeSavedPayload((profile: shownProfile, ringItems: shownRings, unlocks: null, level: 7)), isNull);
      expect(wardrobeSavedPayload(noWardrobeParts), isNull);
    });

    test('a real answer of no unlocks is saved', () {
      expect(wardrobeSavedPayload((profile: shownProfile, ringItems: shownRings, unlocks: [], level: 1)), isNotNull);
    });
  });

  group('wardrobeProfileFromRow', () {
    test('reads the avatar and border', () {
      final p = wardrobeProfileFromRow({'avatar_id': 'wolf', 'avatar_border': 'arc'});
      expect(p.avatarId, 'wolf');
      expect(p.border, AvatarBorderStyle.arc);
    });

    test('a null column is the app default for an account that never picked one', () {
      final p = wardrobeProfileFromRow({'avatar_id': null, 'avatar_border': null});
      expect(p.avatarId, isNull);
      expect(p.border, AvatarBorderStyle.simple);
    });

    test('an unknown stored border throws, so it is a failed read and never a default', () {
      expect(() => wardrobeProfileFromRow({'avatar_id': 'wolf', 'avatar_border': 'sparkly'}), throwsA(anything));
    });
  });

  group('saved copy', () {
    final t0 = DateTime(2026, 11, 17, 12);
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<WardrobeParts?> read(String uid) => SavedCopy.read<WardrobeParts>(uid, 'wardrobe',
        maxAge: kSavedMaxAgeWardrobe, parse: wardrobeFromSaved, now: t0);

    test('the class round trips, and keeps a null avatar and no unlocks', () async {
      final answered = (
        profile: _profile(null, AvatarBorderStyle.arc),
        ringItems: [_ring('red', equipped: true), _ring('blue', owned: false)],
        unlocks: <Map<String, dynamic>>[],
        level: 3,
      );
      await SavedCopy.write(_uid, 'wardrobe', wardrobeSavedPayload(answered)!, now: t0);
      final back = (await read(_uid))!;
      expect(back.profile, answered.profile);
      expect(back.ringItems!.map((i) => i.toSaved()), answered.ringItems.map((i) => i.toSaved()));
      expect(back.unlocks, isEmpty);
      expect(back.level, 3);
    });

    test('the payload survives JSON text', () {
      final back = wardrobeFromSaved(_viaJson(wardrobeSavedPayload(shown)!));
      expect(back.profile, shownProfile);
      expect(back.unlocks, shownUnlocks);
    });

    test('a failed refresh writes nothing, so the saved copy stays', () async {
      await SavedCopy.write(_uid, 'wardrobe', wardrobeSavedPayload(shown)!, now: t0);
      expect(wardrobeSavedPayload(failed), isNull); // the refresh where every read failed
      final back = (await read(_uid))!;
      expect(back.level, 7);
      expect(back.ringItems, hasLength(2));
    });

    test('an empty ring list is corrupt: it reads nothing and is deleted', () async {
      final payload = wardrobeSavedPayload(shown)!..['ring_items'] = [];
      await SavedCopy.write(_uid, 'wardrobe', payload, now: t0);
      expect(await read(_uid), isNull);
      expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.endsWith(':wardrobe')), isEmpty);
    });

    test('another user never reads it', () async {
      await SavedCopy.write(_uid, 'wardrobe', wardrobeSavedPayload(shown)!, now: t0);
      expect(await read('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), isNull);
    });
  });

  group('save safety', () {
    test('built from fresh parts, a selection works and marks it changed', () {
      final s = WardrobeSelectionState.fromParts(shown, editable: true);
      expect(s.avatarId, 'wolf');
      expect(s.ringItem!.id, 'red');
      expect(s.userLevel, 7);
      expect(s.isDirty, isFalse);
      s.setAvatar('lion');
      s.setBorder(AvatarBorderStyle.arc);
      s.setRing(shownRings[1]);
      expect(s.avatarId, 'lion');
      expect(s.border, AvatarBorderStyle.arc);
      expect(s.ringItem!.id, 'blue');
      expect(s.isDirty, isTrue);
    });

    test('built from the saved copy, every selection is ignored and nothing is ever changed', () {
      final s = WardrobeSelectionState.fromParts(shown, editable: false);
      s.setAvatar('lion');
      s.setBorder(AvatarBorderStyle.arc);
      s.setRing(shownRings[1]);
      expect(s.avatarId, 'wolf');
      expect(s.border, AvatarBorderStyle.bold);
      expect(s.ringItem!.id, 'red');
      expect(s.isDirty, isFalse);
    });

    test('built from the saved copy, save throws before it can reach the server', () async {
      final s = WardrobeSelectionState.fromParts(shown, editable: false);
      await expectLater(s.save(), throwsStateError);
    });

    test('the lock state comes from the answered unlocks and level, never from defaults', () {
      final s = WardrobeSelectionState.fromParts(shown, editable: true);
      expect(s.unlockedBorderIds, {'bold'});
      expect(s.userLevel, 7);
    });
  });

  group('strict reads', () {
    Future<CoinService> coins(FakeSupabase server) async {
      await server.signIn(_uid);
      return CoinService(client: server.client);
    }

    Future<LevelService> levels(FakeSupabase server) async {
      await server.signIn(_uid);
      return LevelService(client: server.client);
    }

    Object? shopReply(dynamic req) {
      switch (req.url.pathSegments.last) {
        case 'shop_items':
          return [
            {'id': 'r1', 'name': 'Red Ring', 'category': 'ring_color', 'cost': 10, 'color_hex': '#FF0000'},
            {'id': 'r2', 'name': 'Blue Ring', 'category': 'ring_color', 'cost': 10},
          ];
        case 'user_inventory':
          return [
            {'shop_item_id': 'r1', 'equipped': true},
          ];
      }
      return [];
    }

    FakeSupabase refused() => FakeSupabase()
      ..status = 500
      ..reply = (_) => {'message': 'boom', 'code': 'XX000'};

    test('getShopItems: a failed read is [] by default and rethrown when strict', () async {
      final svc = await coins(refused());
      expect(await svc.getShopItems(), isEmpty);
      await expectLater(svc.getShopItems(strict: true), throwsA(anything));
    });

    test('getShopItems: a complete answer is the same either way', () async {
      final svc = await coins(FakeSupabase()..reply = shopReply);
      final byDefault = await svc.getShopItems();
      final strict = await svc.getShopItems(strict: true);
      for (final items in [byDefault, strict]) {
        expect(items.map((i) => i.id), ['r1', 'r2']);
        expect(items.firstWhere((i) => i.id == 'r1').isEquipped, isTrue);
        expect(items.firstWhere((i) => i.id == 'r2').isOwned, isFalse);
      }
    });

    test('getUnlockedCosmetics: a failed read is [] by default and rethrown when strict', () async {
      final svc = await levels(refused());
      expect(await svc.getUnlockedCosmetics(), isEmpty);
      await expectLater(svc.getUnlockedCosmetics(strict: true), throwsA(anything));
    });

    test('getUnlockedCosmetics: a complete answer is the same either way, and a real [] stays []', () async {
      final rows = [
        {'shop_item_id': 'bold', 'unlock_reason': 'level_3', 'unlocked_at': '2026-11-01T00:00:00Z'},
      ];
      final svc = await levels(FakeSupabase()..reply = (_) => rows);
      expect(await svc.getUnlockedCosmetics(), rows);
      expect(await svc.getUnlockedCosmetics(strict: true), rows);

      final none = await levels(FakeSupabase()..reply = (_) => []);
      expect(await none.getUnlockedCosmetics(strict: true), isEmpty);
    });
  });
}
