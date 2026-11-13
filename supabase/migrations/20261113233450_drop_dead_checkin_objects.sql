-- Dead check-in objects (the "dead-code batch" in dev/hygiene/checkin_rpc_report.md, 07_report.md and
-- 05e_report.md). No caller exists: lib/, supabase/functions/, the cron job commands and every other public
-- function body were searched on 2026-11-13. The one mention left is a comment in _finish_coach_max_checkin.
-- That comment is now stale and gets corrected the next time the function is replaced for another reason
-- (owner decision, 2026-11-13).
--
-- RLS change: drops the INSERT policy "Users can create check-ins for their teams" on
-- public.daily_team_checkins (role public). authenticated has had no INSERT grant on that table since
-- 20261029010000, so the policy admitted nothing. The pin trigger only acted on authenticated/anon inserts,
-- which the missing grant already refused.
--
-- dev/hygiene/suite/grants_fresh.sql (G9.9, G9.12) named the two functions dropped here; it is updated in the
-- same commit.
-- Rollback: dev/rollback_20261113233450.sql

DROP POLICY "Users can create check-ins for their teams" ON public.daily_team_checkins;
DROP TRIGGER pin_client_checkin_date ON public.daily_team_checkins;
DROP FUNCTION public._pin_client_checkin_date();
DROP FUNCTION public.award_checkin_rewards(uuid, date);
DROP FUNCTION public.check_in_coach_max_with_buddy(uuid);
