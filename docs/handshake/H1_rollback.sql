-- Rollback for H1. Run the Phase B reversal first only if Phase B was applied.

-- ── Phase B reversal ────────────────────────────────────────────────────
-- GRANT UPDATE ON public.workouts TO authenticated;
-- CREATE POLICY "Users can update own or buddy workouts" ON public.workouts
--   FOR UPDATE USING ((auth.uid() = user_id) OR (auth.uid() = buddy_id));
-- CREATE POLICY "Users can update their workouts" ON public.workouts
--   FOR UPDATE USING (auth.uid() = user_id);
-- SELECT cron.schedule('reset-expired-ready', '*/5 * * * *', $cron$
--   UPDATE workouts
--   SET creator_ready = false,
--       buddy_ready = false,
--       ready_expires_at = NULL
--   WHERE creator_ready = true
--     AND ready_expires_at IS NOT NULL
--     AND ready_expires_at < NOW()
--     AND status = 'scheduled';
-- $cron$);

-- ── Phase A reversal (20261008180000_handshake_server_phase_a) ──────────
DROP POLICY IF EXISTS "authenticated can join workouts" ON realtime.messages;
ALTER PUBLICATION supabase_realtime DROP TABLE public.workouts;

SELECT cron.unschedule('expire-stale-workout-invites');

DROP FUNCTION IF EXISTS public.expire_stale_workout_invites();
DROP FUNCTION IF EXISTS public.get_workout_card(uuid);
DROP FUNCTION IF EXISTS public.complete_workout(uuid, integer);
DROP FUNCTION IF EXISTS public.change_workout_time(uuid, date, time);
DROP FUNCTION IF EXISTS public.nudge_workout(uuid);
DROP FUNCTION IF EXISTS public.leave_workout(uuid);
DROP FUNCTION IF EXISTS public.cancel_workout(uuid);
DROP FUNCTION IF EXISTS public.go_solo(uuid);
DROP FUNCTION IF EXISTS public.cant_make_it(uuid);
DROP FUNCTION IF EXISTS public.im_here(uuid);
DROP FUNCTION IF EXISTS public.decline_workout_invite(uuid);
DROP FUNCTION IF EXISTS public.accept_workout_invite(uuid, boolean);
DROP FUNCTION IF EXISTS public._workout_card_json(public.workouts, uuid);
DROP FUNCTION IF EXISTS public._hs_lock(uuid);

DROP TRIGGER IF EXISTS set_workout_planned_at ON public.workouts;
DROP FUNCTION IF EXISTS public._set_workout_planned_at();

-- _clamp_client_workout_writes as before H1 (20261002181833 + later).
CREATE OR REPLACE FUNCTION public._clamp_client_workout_writes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- The app only ever creates scheduled workouts.
    IF NEW.status IS DISTINCT FROM 'scheduled' THEN
      RAISE EXCEPTION 'invalid_workout_status' USING ERRCODE = '22023';
    END IF;
    NEW.workout_started_at := NULL;
  ELSE
    -- Every (re)start runs on the server clock; otherwise the start is
    -- immutable, so an old row can't be re-completed against an old start.
    IF NEW.status = 'in_progress' AND OLD.status IS DISTINCT FROM 'in_progress' THEN
      NEW.workout_started_at := now();
    ELSIF NEW.workout_started_at IS DISTINCT FROM OLD.workout_started_at THEN
      NEW.workout_started_at := OLD.workout_started_at;
    END IF;
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed'
       AND OLD.status IS DISTINCT FROM 'in_progress' THEN
      RAISE EXCEPTION 'invalid_workout_status' USING ERRCODE = '22023';
    END IF;
  END IF;

  IF NEW.workout_completed_at > now() THEN
    NEW.workout_completed_at := now();
  END IF;

  -- Never more than the server-measured elapsed time (+1 min for device
  -- clock skew) and never more than 210 min, the auto-complete point.
  -- Only when status/duration change: those columns are then in the SET
  -- list, so the column-scoped >= 15 floor trigger also fires.
  IF NEW.status = 'completed' AND NEW.actual_duration_minutes IS NOT NULL
     AND (TG_OP = 'INSERT'
          OR NEW.actual_duration_minutes IS DISTINCT FROM OLD.actual_duration_minutes
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    NEW.actual_duration_minutes := LEAST(
      NEW.actual_duration_minutes,
      210,
      COALESCE(ceil(extract(epoch FROM now() - NEW.workout_started_at) / 60)::integer + 1, 210)
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- 'expired' rows must go back to a value the old CHECK accepts first.
UPDATE public.workouts SET buddy_status = 'declined' WHERE buddy_status = 'expired';
ALTER TABLE public.workouts
  DROP CONSTRAINT workouts_buddy_status_check,
  ADD CONSTRAINT workouts_buddy_status_check
    CHECK (buddy_status = ANY (ARRAY['pending', 'accepted', 'declined']));

ALTER TABLE public.workouts
  DROP CONSTRAINT IF EXISTS workouts_closed_reason_check,
  DROP COLUMN IF EXISTS closed_reason,
  DROP COLUMN IF EXISTS last_nudge_at,
  DROP COLUMN IF EXISTS planned_at;

-- Ship this as a new forward migration. Never `migration repair --status
-- reverted` 20261008180000 (CLAUDE.md: it deletes history).
