-- 05e RACE-2 session B (committed): testtest1 as authenticated buys Early Adopter (100).
-- A holds its transaction ~8s after the call, then commits. B starts ~2s after A and commits straight away.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'cf4946f5-f921-4e81-bbf4-88d574e8baf5', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE race_out (s text, t0 timestamptz, j jsonb, t1 timestamptz);
INSERT INTO race_out (s, t0) VALUES ('B', clock_timestamp());
UPDATE race_out SET j = public.purchase_shop_item('9eeca178-1353-406d-8671-54e59bdcf26d');
UPDATE race_out SET t1 = clock_timestamp();

RESET ROLE;
COMMIT;
SELECT s, j::text AS result, round(extract(epoch FROM t1 - t0)::numeric, 2) AS call_seconds, t0::text, t1::text, clock_timestamp()::text AS committed_at FROM race_out;
