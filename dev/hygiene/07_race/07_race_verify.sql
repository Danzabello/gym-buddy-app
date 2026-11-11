-- 07 race verify (read-only). Control (bug): R streak 0, no payouts on R; X coins suffixed today 110.
-- Fixed: R streak 1, B 15/15 + A retro 15/15 on R; X coins suffixed today exactly 100.
WITH u(k, id) AS (VALUES ('A onboard_check1', '81f83cdb-e09b-4f1f-8045-afa0d3d2181e'::uuid), ('B onboard_check2', 'bc85514c-02f2-4340-90f2-d95e3f62af26'),
                          ('A'' onboard_check3', 'f0f43430-80aa-4c38-8f87-c11226bef86f'), ('B'' onboard_check6', '30d543f1-bb06-41c4-8522-396ed948ba35'),
                          ('X onboard_check4', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')),
     fx(s) AS (VALUES ('07070707-0000-4000-8000-0000000000b1'), ('07070707-0000-4000-8000-0000000000b2'), ('07070707-0000-4000-8000-0000000000b3')),
     x AS (SELECT public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now())::text AS d),
     r AS (SELECT current_streak, total_workouts, last_workout_date FROM public.team_streaks WHERE id = '07070707-0000-4000-8000-0000000000b1'),
     pay AS (SELECT u.k,
                    (SELECT coalesce(sum(amount), 0) FROM public.xp_transactions t WHERE t.user_id = u.id AND left(t.reference_id, 36) IN (SELECT s FROM fx)) AS xp,
                    (SELECT coalesce(sum(amount), 0) FROM public.coin_transactions t WHERE t.user_id = u.id AND left(t.reference_id, 36) IN (SELECT s FROM fx)) AS coins,
                    (SELECT string_agg(t.description || ':' || t.amount || ':' || substring(t.reference_id from 34 for 3), ' ' ORDER BY t.created_at, t.description)
                     FROM public.coin_transactions t WHERE t.user_id = u.id AND left(t.reference_id, 36) IN (SELECT s FROM fx)) AS coin_rows
             FROM u)
SELECT (SELECT current_streak || '/' || total_workouts || '/' || coalesce(last_workout_date::text, '-') FROM r) AS r_streak_total_last,
       (SELECT count(*) FROM public.daily_team_checkins WHERE team_streak_id = '07070707-0000-4000-8000-0000000000b1') AS r_rows,
       (SELECT coalesce(sum(amount), 0) FROM public.coin_transactions, x WHERE user_id = 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'
          AND transaction_type IN ('daily_checkin', 'partner_bonus') AND substring(reference_id from '[^:]*$') = x.d) AS x_coins_today,
       (SELECT jsonb_object_agg(k, jsonb_build_object('xp', xp, 'coins', coins, 'coin_rows', coin_rows)) FROM pay) AS payouts,
       (SELECT current_streak FROM r) = 0 AND (SELECT sum(coins) FROM pay WHERE k LIKE 'A %' OR k LIKE 'B %') = 0 AS race1_bug_shown,
       (SELECT current_streak FROM r) = 1 AND (SELECT coins FROM pay WHERE k = 'A onboard_check1') = 15 AND (SELECT coins FROM pay WHERE k = 'B onboard_check2') = 15
         AND (SELECT xp FROM pay WHERE k = 'A onboard_check1') = 15 AND (SELECT xp FROM pay WHERE k = 'B onboard_check2') = 15 AS race1_fixed;
