-- Economy table hashes for the Migration A apply window (economy_snapshot.sql with exclusions).
-- Excluded: mijotest's rows (real check-ins), Coach Max test streak d557efec and its check-ins.
-- The 23:05 UTC nightly streak reset is avoided by taking both snapshots on the same side of it.
with x(u, s) as (select '6dfac56a-74a1-4a60-b7fa-e200338350f3'::uuid, 'd557efec-96c6-41af-b43a-8254cd098579'::uuid)
select 'daily_team_checkins' t, count(*) n, md5(coalesce(string_agg(d::text, '|' order by d.id), '')) h from daily_team_checkins d, x where d.user_id <> x.u and d.team_streak_id <> x.s
union all select 'workout_logs', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from workout_logs d, x where d.user_id <> x.u
union all select 'xp_transactions', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from xp_transactions d, x where d.user_id <> x.u
union all select 'coin_transactions', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from coin_transactions d, x where d.user_id <> x.u
union all select 'team_streaks', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from team_streaks d, x where d.id <> x.s
union all select 'user_profiles_xp_coins', count(*), md5(coalesce(string_agg(d.id||':'||d.xp||':'||d.coin_balance, '|' order by d.id), '')) from user_profiles d, x where d.id <> x.u
union all select 'workouts', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from workouts d, x where d.user_id <> x.u and d.buddy_id is distinct from x.u
union all select 'invites', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from invites d
union all select 'user_unlocked_cosmetics', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from user_unlocked_cosmetics d
union all select 'snapshot_at', 0, now()::text
