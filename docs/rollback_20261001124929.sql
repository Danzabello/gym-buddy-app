-- ROLLBACK for supabase/migrations/20261001124929_award_checkin_rewards_date_window.sql
-- NOT a migration: lives in docs/ on purpose so `supabase db push` never runs it.
--
-- Restores the pre-fix body of award_checkin_rewards(uuid, date), captured with
-- pg_get_functiondef on 2026-10-01 (no date window). Re-opens LIVE-22 reward
-- claims for arbitrary dates; only run to unblock a regression. If a later
-- migration has since replaced this function, DO NOT run this.
--
-- Run as postgres (SQL editor or `supabase db query`). Idempotent.
BEGIN;

CREATE OR REPLACE FUNCTION public.award_checkin_rewards(p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_team_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT team_id INTO v_team_id FROM team_streaks WHERE id = p_streak_id;
  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'invalid_streak';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM team_members WHERE team_id = v_team_id AND user_id = v_caller
  ) THEN
    RAISE EXCEPTION 'not_a_team_member';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id AND user_id = v_caller AND check_in_date = p_check_in_date
  ) THEN
    RAISE EXCEPTION 'no_checkin_found_for_caller';
  END IF;

  RETURN public._apply_checkin_rewards(v_caller, p_streak_id, p_check_in_date);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) TO authenticated;

COMMIT;
