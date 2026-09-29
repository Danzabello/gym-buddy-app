-- ROLLBACK for supabase/migrations/20260929210000_revoke_truncate_and_anon_writes.sql
-- NOT a migration: lives in docs/ on purpose so `supabase db push` never runs it.
--
-- Restores EXACTLY the table-level grants that existed on the live project at
-- the time the migration was drafted (captured with aclexplode(pg_class.relacl)
-- on 2026-09-29), no more and no less:
--   * authenticated: TRUNCATE on all 33 tables listed below
--   * anon: the per-table INSERT / UPDATE / DELETE / TRUNCATE sets below (32 tables)
-- It does NOT restore anything for tables created after that date; grant those
-- by hand if you need them back. Column-level grants are untouched by both files.
--
-- Run as postgres (SQL editor or `supabase db query`). Idempotent.
BEGIN;

-- authenticated: TRUNCATE
GRANT TRUNCATE ON public.achievements TO authenticated;
GRANT TRUNCATE ON public.active_checkin_sessions TO authenticated;
GRANT TRUNCATE ON public.break_day_usage TO authenticated;
GRANT TRUNCATE ON public.buddy_nudges TO authenticated;
GRANT TRUNCATE ON public.buddy_teams TO authenticated;
GRANT TRUNCATE ON public.check_ins TO authenticated;
GRANT TRUNCATE ON public.coach_max_schedule TO authenticated;
GRANT TRUNCATE ON public.coin_transactions TO authenticated;
GRANT TRUNCATE ON public.cosmetic_unlock_conditions TO authenticated;
GRANT TRUNCATE ON public.daily_check_ins TO authenticated;
GRANT TRUNCATE ON public.daily_team_checkins TO authenticated;
GRANT TRUNCATE ON public.device_tokens TO authenticated;
GRANT TRUNCATE ON public.friend_nicknames TO authenticated;
GRANT TRUNCATE ON public.friendships TO authenticated;
GRANT TRUNCATE ON public.invite_reward_dead_letters TO authenticated;
GRANT TRUNCATE ON public.invites TO authenticated;
GRANT TRUNCATE ON public.level_definitions TO authenticated;
GRANT TRUNCATE ON public.notification_log TO authenticated;
GRANT TRUNCATE ON public.notification_settings TO authenticated;
GRANT TRUNCATE ON public.shop_items TO authenticated;
GRANT TRUNCATE ON public.team_members TO authenticated;
GRANT TRUNCATE ON public.team_names TO authenticated;
GRANT TRUNCATE ON public.team_streaks TO authenticated;
GRANT TRUNCATE ON public.user_achievements TO authenticated;
GRANT TRUNCATE ON public.user_profiles TO authenticated;
GRANT TRUNCATE ON public.user_unlocked_cosmetics TO authenticated;
GRANT TRUNCATE ON public.weekly_break_plans TO authenticated;
GRANT TRUNCATE ON public.weekly_commitments TO authenticated;
GRANT TRUNCATE ON public.workout_invites TO authenticated;
GRANT TRUNCATE ON public.workout_logs TO authenticated;
GRANT TRUNCATE ON public.workout_templates TO authenticated;
GRANT TRUNCATE ON public.workouts TO authenticated;
GRANT TRUNCATE ON public.xp_transactions TO authenticated;

-- anon: INSERT / UPDATE / DELETE / TRUNCATE (per-table sets as they were)
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.achievements TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.active_checkin_sessions TO anon;
GRANT INSERT, TRUNCATE, UPDATE ON public.break_day_usage TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.buddy_nudges TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.buddy_teams TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.check_ins TO anon;
GRANT DELETE, INSERT, TRUNCATE ON public.coach_max_schedule TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.coin_transactions TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.cosmetic_unlock_conditions TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.daily_check_ins TO anon;
GRANT DELETE, TRUNCATE, UPDATE ON public.daily_team_checkins TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.device_tokens TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.friend_nicknames TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.friendships TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.invite_reward_dead_letters TO anon;
GRANT INSERT, TRUNCATE ON public.invites TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.level_definitions TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.notification_log TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.notification_settings TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.shop_items TO anon;
GRANT DELETE, TRUNCATE, UPDATE ON public.team_members TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.team_names TO anon;
GRANT DELETE, INSERT, TRUNCATE ON public.team_streaks TO anon;
GRANT DELETE, TRUNCATE ON public.user_profiles TO anon;
GRANT DELETE, TRUNCATE, UPDATE ON public.user_unlocked_cosmetics TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.weekly_break_plans TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.weekly_commitments TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.workout_invites TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.workout_logs TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.workout_templates TO anon;
GRANT DELETE, INSERT, TRUNCATE, UPDATE ON public.workouts TO anon;
GRANT DELETE, TRUNCATE, UPDATE ON public.xp_transactions TO anon;

-- Verify (tables holding any of the four privileges): expect 33 for authenticated
-- and 32 for anon, matching the state captured when this was drafted:
--   select r.rolname, count(distinct c.relname) as tables
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
--   cross join lateral aclexplode(c.relacl) a join pg_roles r on r.oid=a.grantee
--   where c.relkind in ('r','p') and r.rolname in ('anon','authenticated')
--     and a.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
--   group by r.rolname;
COMMIT;
