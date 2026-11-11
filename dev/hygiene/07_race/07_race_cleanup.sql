-- 07 race cleanup (COMMITTED in the approved rounds), as postgres, one transaction.
-- Baseline for the five accounts: 0 xp/coin transaction rows, 0 check-in rows, 5 team_members rows (their Coach Max
-- teams), profile row md5s as in the seed. So every transaction or check-in row they now have was written by the race.
-- Deletes them, deletes the 3 fixture teams (cascades members, streaks, streak_events), restores xp/coins/level,
-- then the guard aborts the WHOLE cleanup unless all five are back to the exact baseline.
BEGIN;
-- BODY START
DELETE FROM public.xp_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')
  AND left(reference_id, 36) IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3');
DELETE FROM public.coin_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')
  AND left(reference_id, 36) IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3');
DELETE FROM public.daily_team_checkins WHERE team_streak_id IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3');
DELETE FROM public.buddy_teams WHERE id IN ('07070707-0000-4000-8000-0000000000a1', '07070707-0000-4000-8000-0000000000a2', '07070707-0000-4000-8000-0000000000a3');
UPDATE public.user_profiles SET xp = 0, coin_balance = 0, level = 1
WHERE id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9');
DO $guard$
BEGIN
  IF (SELECT string_agg(md5(p::text), ' ' ORDER BY id) FROM public.user_profiles p
      WHERE id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f',
                   '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     IS DISTINCT FROM 'ceac7404e055d8f3de55f81945402aff 47582882a823e6f714a2bdb67877d831 efb30bff79736c2bc6f93052c341a62c e28694d729e229950b5d14f208db4e97 f549813160ebe131b16e6d5d109a3798'
     OR EXISTS (SELECT 1 FROM public.xp_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.coin_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.daily_team_checkins WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR (SELECT count(*) FROM public.team_members WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')) <> 5
     OR EXISTS (SELECT 1 FROM public.buddy_teams WHERE id IN ('07070707-0000-4000-8000-0000000000a1', '07070707-0000-4000-8000-0000000000a2', '07070707-0000-4000-8000-0000000000a3'))
     OR EXISTS (SELECT 1 FROM public.team_streaks WHERE id IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3')) THEN
    RAISE EXCEPTION 'race07 cleanup: not back to baseline; whole cleanup rolled back';
  END IF;
END $guard$;
-- BODY END
COMMIT;
SELECT 'cleaned' AS s, now()::text AS at;
