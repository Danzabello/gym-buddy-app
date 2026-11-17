import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/coin_service.dart';

import 'support/fake_supabase.dart';

const _me = '11111111-1111-4111-8111-111111111111';

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

  group('CoinService.getBalanceOrNull', () {
    test('a real balance of 0 is 0, not null', () async {
      final server = FakeSupabase()..reply = (_) => {'coin_balance': 0};
      await server.signIn(_me);
      expect(await CoinService(client: server.client).getBalanceOrNull(), 0);
    });

    test('a failed read is null, while getBalance keeps answering 0', () async {
      final server = FakeSupabase()..status = 400;
      await server.signIn(_me);
      final svc = CoinService(client: server.client);
      expect(await svc.getBalanceOrNull(), isNull);
      expect(await svc.getBalance(), 0);
    });

    test('nobody signed in is null', () async {
      final server = FakeSupabase();
      expect(await CoinService(client: server.client).getBalanceOrNull(), isNull);
      expect(server.calls, isEmpty);
    });
  });
}
