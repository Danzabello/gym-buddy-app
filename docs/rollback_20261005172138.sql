-- ROLLBACK for supabase/migrations/20261005172138_checkin_sessions_own_rows_only.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores the four linked_workout_id policies, anon's table grants and the
-- previous _pin_client_session_start body (M1, 20261002181833). Run as postgres.
-- WARNING: this reopens the session-planting hole.
BEGIN;
CREATE POLICY "Users can create sessions for themselves or workout buddies" ON public.active_checkin_sessions
  FOR INSERT WITH CHECK ((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM workouts w
  WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id)))))));
CREATE POLICY "Users can delete their own sessions or linked buddy sessions" ON public.active_checkin_sessions
  FOR DELETE USING ((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM workouts w
  WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id)))))));
CREATE POLICY "Users can update their own sessions or linked buddy sessions" ON public.active_checkin_sessions
  FOR UPDATE USING ((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM workouts w
  WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id)))))));
CREATE POLICY "Users can view their own sessions or workout buddy sessions" ON public.active_checkin_sessions
  FOR SELECT USING ((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM workouts w
  WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id)))))));
GRANT SELECT, REFERENCES, TRIGGER, MAINTAIN ON public.active_checkin_sessions TO anon;
CREATE OR REPLACE FUNCTION public._pin_client_session_start()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.workout_id IS NOT NULL AND NEW.started_at = (
    SELECT w.workout_started_at FROM workouts w
    WHERE w.id = NEW.workout_id AND auth.uid() IN (w.user_id, w.buddy_id)
  ) THEN
    RETURN NEW;
  END IF;

  NEW.started_at := CASE WHEN TG_OP = 'INSERT' THEN now() ELSE OLD.started_at END;
  RETURN NEW;
END;
$$;
COMMIT;
