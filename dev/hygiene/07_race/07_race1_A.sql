-- 07 race session race1 A onboard_check1 (COMMITTED in the approved rounds). As postgres; one credit on a fixture streak only.
BEGIN;
SELECT set_config('app.checkin_copy', '1', true);  -- no buddy push for fixture rows
CREATE TEMP TABLE race_out (s text, t0 timestamptz, j jsonb, t1 timestamptz);
INSERT INTO race_out (s, t0) VALUES ('race1 A onboard_check1', clock_timestamp());
UPDATE race_out SET j = public._credit_checkin('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', now(), true, now(), '07070707-0000-4000-8000-0000000000b1');
UPDATE race_out SET t1 = clock_timestamp();
SELECT pg_sleep(8);  -- hold ~8 s, B starts ~2 s after A
COMMIT;
SELECT s, j::text AS result, round(extract(epoch FROM t1 - t0)::numeric, 2) AS call_seconds, t0::text, t1::text, clock_timestamp()::text AS committed_at FROM race_out;
