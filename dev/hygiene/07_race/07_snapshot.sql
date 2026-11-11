-- Economy table hashes for prompt 07 (checkin_rpc_snapshot.sql plus team tables, streak_events and the five race accounts).
-- Excluded: mijotest's rows (real check-ins), Coach Max test streak d557efec and its check-ins. Taken outside 22:55-23:15 UTC.
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
union all select 'buddy_teams', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from buddy_teams d
union all select 'team_members', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from team_members d
union all select 'streak_events', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from streak_events d
union all select 'race07_profiles', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from user_profiles d
  where d.id in ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')
order by 1
