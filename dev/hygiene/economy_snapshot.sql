select 'daily_team_checkins' t, count(*) n, md5(coalesce(string_agg(d::text, '|' order by d.id), '')) h from daily_team_checkins d
union all select 'workout_logs', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from workout_logs d
union all select 'xp_transactions', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from xp_transactions d
union all select 'coin_transactions', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from coin_transactions d
union all select 'team_streaks', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from team_streaks d
union all select 'user_profiles_xp_coins', count(*), md5(coalesce(string_agg(d.id||':'||d.xp||':'||d.coin_balance, '|' order by d.id), '')) from user_profiles d
union all select 'workouts', count(*), md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from workouts d
