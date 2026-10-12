-- Hygiene 05c (Phase C, destructive). Backup + dry run: docs/hygiene/05c_backup/, docs/hygiene/05c_dry_run_output.txt
-- Rollback: docs/rollback_20261013002000.sql
-- C1 legacy handshake: table workout_invites and its trigger functions, is_user_in_active_workout, the dead join-popup RPC and columns.
DROP TABLE public.workout_invites;
DROP FUNCTION public.notify_workout_invite();
DROP FUNCTION public.notify_workout_invite_response();
DROP FUNCTION public.is_user_in_active_workout(uuid);
DROP FUNCTION public.get_workouts_awaiting_creator_join(uuid);
ALTER TABLE public.workouts DROP COLUMN ready_expires_at, DROP COLUMN creator_popup_shown;
ALTER TABLE public.user_profiles DROP COLUMN workout_join_popups_enabled;

-- Partner credit hole: any participant of any workout (even one never started) could credit the other.
REVOKE EXECUTE ON FUNCTION public.checkin_team_for_user(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Team names embed display names ("A & B"); scrub the deleted user's name. Never raises: account deletion must not depend on it.
CREATE OR REPLACE FUNCTION public._scrub_team_names_on_profile_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    IF OLD.display_name IS NOT NULL AND btrim(OLD.display_name) <> '' THEN
      UPDATE buddy_teams bt
         SET team_name = (SELECT string_agg(CASE WHEN lower(btrim(u.p)) = lower(btrim(OLD.display_name)) THEN 'Former buddy' ELSE u.p END, ' & ' ORDER BY u.o)
                            FROM unnest(string_to_array(bt.team_name, ' & ')) WITH ORDINALITY AS u(p, o))
       WHERE coalesce(bt.is_coach_max_team, false) = false
         AND bt.team_name IS NOT NULL
         AND position(lower(btrim(OLD.display_name)) IN lower(bt.team_name)) > 0
         AND bt.id IN (SELECT tm.team_id FROM team_members tm WHERE tm.user_id = OLD.id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN OLD;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._scrub_team_names_on_profile_delete() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER scrub_team_names_on_profile_delete BEFORE DELETE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public._scrub_team_names_on_profile_delete();

-- Unused vault secret named with the anon JWT; its value duplicated service_role_key (which stays). No consumers anywhere.
DELETE FROM vault.secrets WHERE id = 'fbae4dec-efe3-48ca-9230-9f326a206e48';

-- C2 DB-9: six test-only teams. Aborts if any member is not a known test account or any team has workout_logs.
DO $$
DECLARE v_ids uuid[] := ARRAY['d168695d-f788-477a-80e7-78bb1c7b876b','bd6736f1-410c-483f-939a-3119ac08d5c8','dc1ee1ab-d474-4ffd-a540-ef059511d1fd','2a45a481-d14d-4590-a188-92b8cf21c43c','0e596a48-aee5-4b9b-afbe-9dae16740a61','c2e4b37e-f54e-45fb-88f7-9c7f9a33ba10']::uuid[];
BEGIN
  IF EXISTS (SELECT 1 FROM team_members WHERE team_id = ANY(v_ids) AND user_id NOT IN ('5e67f64d-16e3-4b09-9b00-ddc49df8c3f6','6ef4e82e-a54d-4b91-8ce4-b5f179a65f66','cf4946f5-f921-4e81-bbf4-88d574e8baf5','6dfac56a-74a1-4a60-b7fa-e200338350f3','f7c1ef63-3b93-401d-b2bb-8402ddf9a881','00000000-0000-0000-0000-000000000001')) THEN
    RAISE EXCEPTION 'hygiene_05c: non-test member in a team scheduled for deletion';
  END IF;
  IF EXISTS (SELECT 1 FROM workout_logs WHERE team_id = ANY(v_ids)) THEN
    RAISE EXCEPTION 'hygiene_05c: workout_logs reference a team scheduled for deletion';
  END IF;
  DELETE FROM streak_events WHERE team_id = ANY(v_ids);
  DELETE FROM daily_team_checkins WHERE team_streak_id IN (SELECT id FROM team_streaks WHERE team_id = ANY(v_ids));
  DELETE FROM team_streaks WHERE team_id = ANY(v_ids);
  DELETE FROM team_members WHERE team_id = ANY(v_ids);
  DELETE FROM buddy_teams WHERE id = ANY(v_ids);
END
$$;
