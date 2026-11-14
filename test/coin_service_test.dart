import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/coin_service.dart';

import 'support/fake_supabase.dart';

void main() {
  group('CoinService.equipItem', () {
    test('sends one equip_shop_item call and no table write', () async {
      final server = FakeSupabase()..reply = (_) => true;
      final ok = await CoinService(client: server.client).equipItem(itemId: 'ring-1');

      expect(ok, isTrue);
      expect(server.calls, hasLength(1));
      expect(server.calls.single.method, 'POST');
      expect(server.target(0), 'equip_shop_item');
      expect(server.body(0), {'p_shop_item_id': 'ring-1'});
    });

    test('an item the server refuses is reported as not equipped', () async {
      final server = FakeSupabase()..reply = (_) => false;
      expect(await CoinService(client: server.client).equipItem(itemId: 'x'), isFalse);
      expect(server.calls, hasLength(1));
    });

    test('a server error or a dropped connection is false, not thrown', () async {
      final refused = FakeSupabase()
        ..status = 403
        ..reply = (_) => {'message': 'permission denied', 'code': '42501'};
      expect(await CoinService(client: refused.client).equipItem(itemId: 'x'), isFalse);

      final offline = FakeSupabase()..down = true;
      expect(await CoinService(client: offline.client).equipItem(itemId: 'x'), isFalse);
    });
  });
}
