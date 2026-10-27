-- 05d race session A: testtest1 (balance 0) buys Early Adopter; the call returns insufficient_funds, so no write.
-- Session A holds its transaction open 8s after the call; B starts ~2s later and reports how long its call took. RAISE rolls back.
DO $race$
DECLARE t0 timestamptz; j jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', 'cf4946f5-f921-4e81-bbf4-88d574e8baf5', 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  t0 := clock_timestamp();
  j := public.purchase_shop_item('9eeca178-1353-406d-8671-54e59bdcf26d');
  PERFORM pg_sleep(8);
  RAISE EXCEPTION 'RACE_A call_seconds=% reason=%', round(extract(epoch FROM clock_timestamp() - t0)::numeric, 2), j->>'reason';
END
$race$;
