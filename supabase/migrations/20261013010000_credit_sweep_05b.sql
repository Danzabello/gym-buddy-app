-- Credit sweep 05b. Sweep and verdicts: docs/hygiene/05b_sweep.md. Backup: docs/hygiene/05b_backup/
-- Rollback: docs/rollback_20261013010000.sql

-- checkin_team_for_user: credited a workout partner with no workout (05c probe). No callers in DB, Dart, edge or cron;
-- EXECUTE already revoked in 05c. finish_checkin_session is the only client partner-credit path left.
DROP FUNCTION public.checkin_team_for_user(uuid, uuid);

-- 4 leftover test teams (each has one remaining test member). Aborts if a member is not one of those accounts,
-- the Coach Max bot is involved, the protected streak d557efec is hit, or any team has workout_logs.
DO $$
DECLARE v_ids uuid[] := ARRAY['05c20a6a-e239-47e2-93c0-347e6324e927','3847194a-24c5-48c4-a7b7-1858011bc730','a3ae42dc-8fb4-4c70-b4b5-2bcf5120f080','c06f57ea-0868-46b8-8887-489a008efe78']::uuid[];
BEGIN
  IF EXISTS (SELECT 1 FROM team_members WHERE team_id = ANY(v_ids) AND user_id NOT IN ('07960b8c-300b-44cb-89dd-93f3f38099b8','2b61ae0f-655f-4111-b754-b18e00afe9d8','5e5c9752-7ff9-4b67-8800-915c2515d88b','64de5abb-df2e-4d87-b80a-4dc70742df86')) THEN
    RAISE EXCEPTION 'credit_sweep_05b: unexpected member in a team scheduled for deletion';
  END IF;
  IF EXISTS (SELECT 1 FROM buddy_teams WHERE id = ANY(v_ids) AND is_coach_max_team)
     OR EXISTS (SELECT 1 FROM team_streaks WHERE team_id = ANY(v_ids) AND id = 'd557efec-96c6-41af-b43a-8254cd098579') THEN
    RAISE EXCEPTION 'credit_sweep_05b: Coach Max team or protected streak scheduled for deletion';
  END IF;
  IF EXISTS (SELECT 1 FROM workout_logs WHERE team_id = ANY(v_ids)) THEN
    RAISE EXCEPTION 'credit_sweep_05b: workout_logs reference a team scheduled for deletion';
  END IF;
  DELETE FROM streak_events WHERE team_id = ANY(v_ids);
  DELETE FROM daily_team_checkins WHERE team_streak_id IN (SELECT id FROM team_streaks WHERE team_id = ANY(v_ids));
  DELETE FROM team_streaks WHERE team_id = ANY(v_ids);
  DELETE FROM team_members WHERE team_id = ANY(v_ids);
  DELETE FROM buddy_teams WHERE id = ANY(v_ids);
END
$$;
