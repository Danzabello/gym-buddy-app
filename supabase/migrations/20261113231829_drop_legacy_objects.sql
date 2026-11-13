-- Legacy objects with no caller (tracker LIVE-21).
-- Evidence (2026-11-13): no reference in lib/ or supabase/functions/; no cron job, policy, view, column
-- default or trigger references them; the only function bodies that do are three of the functions dropped here
-- (can_take_rest_day and get_current_weekly_commitment read weekly_commitments, get_random_team_name reads
-- team_names); the only foreign key into the tables is daily_check_ins -> weekly_commitments (both dropped here). Row counts on live: check_ins 0, daily_check_ins 0, weekly_commitments 0, team_names 30
-- (seed names, kept in the rollback file).
--
-- RLS and grant change: dropping the tables removes their 13 policies and their grants:
--   check_ins (4 policies: own-row SELECT/INSERT/UPDATE/DELETE), daily_check_ins (4, same shape),
--   weekly_commitments (4, same shape), team_names ("Anyone can view team names", SELECT).
-- EXECUTE on the six functions goes with them (four were executable by authenticated; none has a client caller).
--
-- NOT included, on purpose: cosmetic_unlock_conditions and user_unlocked_cosmetics (award_xp still reads and
-- writes them, and the wardrobe reads user_unlocked_cosmetics), invite_reward_dead_letters (written by the
-- invite reward trigger).
-- Rollback: dev/rollback_20261113231829.sql

DROP FUNCTION public.can_take_rest_day(uuid);
DROP FUNCTION public.get_current_weekly_commitment(uuid);
DROP FUNCTION public.get_random_team_name();
DROP FUNCTION public.check_team_streak_status(uuid, date);
DROP FUNCTION public.get_team_checkin_order(uuid, date);
DROP FUNCTION public.delete_own_account();

DROP TABLE public.check_ins;
DROP TABLE public.daily_check_ins;
DROP TABLE public.weekly_commitments;
DROP TABLE public.team_names;
