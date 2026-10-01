-- LIVE-24 (a): columns for server auto-completion (read by 03b), client
-- input guards on workouts / workout_logs / coach_max_schedule, and a cap of
-- 4 completed workouts per user per local day.
--
-- auto_completed = the server closed it (process_stale_sessions). Paid
-- auto-completions are status 'completed'; closed-without-credit ones are
-- status 'cancelled' (workouts only). The client may only stamp
-- auto_completed_notice_seen_at, once.
-- Guards apply to client roles only (same test as _pin_client_checkin_date);
-- SECURITY DEFINER paths run as postgres and are untouched.

ALTER TABLE public.workouts
  ADD COLUMN auto_completed boolean NOT NULL DEFAULT false,
  ADD COLUMN auto_completed_notice_seen_at timestamptz;

ALTER TABLE public.workout_logs
  ADD COLUMN auto_completed boolean NOT NULL DEFAULT false,
  ADD COLUMN auto_completed_notice_seen_at timestamptz;

-- Push dedup for process_stale_sessions (#1 at goal, #2 one hour later).
ALTER TABLE public.active_checkin_sessions
  ADD COLUMN goal_notified_at timestamptz,
  ADD COLUMN reminder_notified_at timestamptz;

-- ── auto_completed flags: server-only; notice seen-at settable once ──────
CREATE OR REPLACE FUNCTION public._guard_client_auto_complete_flags()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.auto_completed := false;
    NEW.auto_completed_notice_seen_at := NULL;
    RETURN NEW;
  END IF;

  IF NEW.auto_completed IS DISTINCT FROM OLD.auto_completed THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF NEW.auto_completed_notice_seen_at IS DISTINCT FROM OLD.auto_completed_notice_seen_at THEN
    IF OLD.auto_completed_notice_seen_at IS NOT NULL OR NEW.auto_completed_notice_seen_at IS NULL THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
    NEW.auto_completed_notice_seen_at := now();
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER guard_client_auto_complete_flags
  BEFORE INSERT OR UPDATE ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public._guard_client_auto_complete_flags();

CREATE TRIGGER guard_client_auto_complete_flags
  BEFORE INSERT OR UPDATE ON public.workout_logs
  FOR EACH ROW EXECUTE FUNCTION public._guard_client_auto_complete_flags();

-- ── workouts: server clock decides start, end and duration ───────────────
-- Named to sort before enforce_workout_completion_duration (BEFORE triggers
-- fire alphabetically), so the >= 15 floor checks the clamped value.
CREATE OR REPLACE FUNCTION public._clamp_client_workout_writes()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
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
$$;

CREATE TRIGGER clamp_client_workout_writes
  BEFORE INSERT OR UPDATE ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public._clamp_client_workout_writes();

-- ── workouts: max 4 completed per user per local day (all roles) ─────────
-- SECURITY DEFINER so the count sees every row of the creator, not just the
-- rows the caller's RLS shows (a buddy completing the creator's workout).
CREATE OR REPLACE FUNCTION public._enforce_workout_daily_cap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text;
  v_day date;
BEGIN
  IF NEW.status IS DISTINCT FROM 'completed'
     OR (TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM 'completed') THEN
    RETURN NEW;
  END IF;

  v_tz := public.safe_user_tz(NEW.user_id);
  v_day := (COALESCE(NEW.workout_completed_at, now()) AT TIME ZONE v_tz)::date;

  PERFORM pg_advisory_xact_lock(hashtext('workout_daily_cap:' || NEW.user_id::text));

  IF (SELECT count(*) FROM workouts
      WHERE user_id = NEW.user_id
        AND status = 'completed'
        AND id <> NEW.id
        AND (workout_completed_at AT TIME ZONE v_tz)::date = v_day) >= 4 THEN
    RAISE EXCEPTION 'daily_workout_limit_reached' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_workout_daily_cap
  BEFORE INSERT OR UPDATE ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public._enforce_workout_daily_cap();

-- ── coach_max_schedule: the client may schedule, never mark checked in ───
-- special_path_robot counts has_checked_in; only the server sets it
-- (_finish_coach_max_checkin, coach-max-cron). Client UPDATE is already
-- ungranted; DELETE was granted but unused (and had no policy).
CREATE OR REPLACE FUNCTION public._clamp_client_coach_max_schedule()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.has_checked_in := false;
    NEW.checked_in_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER clamp_client_coach_max_schedule
  BEFORE INSERT ON public.coach_max_schedule
  FOR EACH ROW EXECUTE FUNCTION public._clamp_client_coach_max_schedule();

REVOKE DELETE ON public.coach_max_schedule FROM authenticated;
