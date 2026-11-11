-- 07 race seed (COMMITTED in the approved rounds). As postgres. Fixture ids are fixed literals (no fixture table).
-- Accounts (matched by id): A onboard_check1 81f83cdb, B onboard_check2 bc85514c (RACE-1);
--   A' onboard_check3 f0f43430, B' onboard_check6 30d543f1, X onboard_check4 ae240bb6 (CAP-RACE).
-- Teams: R 07070707-…-a1 (A, B), streak …-b1; S1 …-a2 (A', X), streak …-b2; S2 …-a3 (B', X), streak …-b3.
-- Aborts unless all five accounts are exactly at baseline (profile row md5s read 2026-10-29 16:44 UTC).
BEGIN;
-- BODY START
SELECT set_config('app.checkin_copy', '1', true);  -- fixture rows send no buddy push
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
     OR EXISTS (SELECT 1 FROM public.invites WHERE accepted_by IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.active_checkin_sessions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.break_day_usage WHERE cancelled_at IS NULL AND break_date >= current_date - 1 AND user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.buddy_teams WHERE id IN ('07070707-0000-4000-8000-0000000000a1', '07070707-0000-4000-8000-0000000000a2', '07070707-0000-4000-8000-0000000000a3')) THEN
    RAISE EXCEPTION 'race07 seed: baseline changed; not seeding';
  END IF;
END $guard$;

INSERT INTO public.buddy_teams (id, team_name, team_emoji, is_coach_max_team, max_members, created_by) VALUES
  ('07070707-0000-4000-8000-0000000000a1', '07-race1', '💪', false, 2, '81f83cdb-e09b-4f1f-8045-afa0d3d2181e'),
  ('07070707-0000-4000-8000-0000000000a2', '07-cap-s1', '💪', false, 2, 'f0f43430-80aa-4c38-8f87-c11226bef86f'),
  ('07070707-0000-4000-8000-0000000000a3', '07-cap-s2', '💪', false, 2, '30d543f1-bb06-41c4-8522-396ed948ba35');
INSERT INTO public.team_members (team_id, user_id, role) VALUES
  ('07070707-0000-4000-8000-0000000000a1', '81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'member'),
  ('07070707-0000-4000-8000-0000000000a1', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'member'),
  ('07070707-0000-4000-8000-0000000000a2', 'f0f43430-80aa-4c38-8f87-c11226bef86f', 'member'),
  ('07070707-0000-4000-8000-0000000000a2', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', 'member'),
  ('07070707-0000-4000-8000-0000000000a3', '30d543f1-bb06-41c4-8522-396ed948ba35', 'member'),
  ('07070707-0000-4000-8000-0000000000a3', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', 'member');
INSERT INTO public.team_streaks (id, team_id, current_streak, longest_streak, is_active) VALUES
  ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000a1', 0, 0, true),
  ('07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000a2', 0, 0, true),
  ('07070707-0000-4000-8000-0000000000b3', '07070707-0000-4000-8000-0000000000a3', 0, 0, true);
-- X already checked in today on S1 and S2, and already has 90 coins of check-in payouts suffixed today (room 10).
INSERT INTO public.daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES
  ('07070707-0000-4000-8000-0000000000b2', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now()), now()),
  ('07070707-0000-4000-8000-0000000000b3', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now()), now());
INSERT INTO public.coin_transactions (user_id, amount, transaction_type, description, reference_id) VALUES
  ('ae240bb6-e629-401e-9fb6-feb1ed21cee9', 90, 'daily_checkin', 'race07 seed (ledger only)',
   '07070707-0000-4000-8000-0000000000b2:seed:' || public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now()));
-- BODY END
COMMIT;
SELECT 'seeded' AS s, now()::text AS at;
