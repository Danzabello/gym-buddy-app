-- H1 Phase A: server-side handshake for the Workout Schedule card.
-- Additive only: the installed app keeps writing workouts directly until
-- Phase B (docs/handshake/H1_phase_b_lockdown.sql, applied in H4).
-- Error codes are the RAISE message: not_authenticated, not_found,
-- not_participant, wrong_state, too_early, window_closed, already_in_workout,
-- invite_cap_reached, nudge_too_soon, not_creator, not_invitee.

-- ── Columns ─────────────────────────────────────────────────────────────
ALTER TABLE public.workouts
  ADD COLUMN planned_at timestamptz,
  ADD COLUMN last_nudge_at timestamptz,
  ADD COLUMN closed_reason text,
  ADD CONSTRAINT workouts_closed_reason_check CHECK (closed_reason IN (
    'declined', 'expired', 'cancelled_by_creator', 'buddy_cant_make_it',
    'left', 'solo_abandoned', 'completed', 'auto'));

ALTER TABLE public.workouts
  DROP CONSTRAINT workouts_buddy_status_check,
  ADD CONSTRAINT workouts_buddy_status_check
    CHECK (buddy_status = ANY (ARRAY['pending', 'accepted', 'declined', 'expired']));

-- ── planned_at: date + time in the inviter's own zone ───────────────────
CREATE FUNCTION public._set_workout_planned_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public
AS $$
BEGIN
  NEW.planned_at := (NEW.workout_date + NEW.workout_time) AT TIME ZONE public.safe_user_tz(NEW.user_id);
  RETURN NEW;
END;
$$;

-- planned_at in the column list: a client can't write it directly.
CREATE TRIGGER set_workout_planned_at
  BEFORE INSERT OR UPDATE OF workout_date, workout_time, user_id, planned_at ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public._set_workout_planned_at();

UPDATE public.workouts
SET planned_at = (workout_date + workout_time) AT TIME ZONE public.safe_user_tz(user_id);

-- ── Client inserts: safe defaults + 5 open invites per sender ───────────
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
    -- A new invite is unanswered and nobody is "here" yet.
    NEW.buddy_status := 'pending';
    NEW.creator_ready := false;
    NEW.buddy_ready := false;
    NEW.creator_cancelled := false;
    NEW.buddy_cancelled := false;
    NEW.last_nudge_at := NULL;
    NEW.closed_reason := NULL;
    IF NEW.buddy_id IS NOT NULL THEN
      PERFORM pg_advisory_xact_lock(hashtext('invite_cap:' || NEW.user_id::text));
      IF (SELECT count(*) FROM workouts
          WHERE user_id = NEW.user_id AND status = 'scheduled' AND buddy_status = 'pending'
            AND buddy_id IS NOT NULL AND planned_at + interval '15 minutes' >= now()) >= 5 THEN
        RAISE EXCEPTION 'invite_cap_reached';
      END IF;
    END IF;
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

-- ── Internal helpers (not client-callable) ──────────────────────────────
-- Locks the row and checks the caller is one of its two people.
CREATE FUNCTION public._hs_lock(p_workout_id uuid)
 RETURNS public.workouts
 LANGUAGE plpgsql
 SET search_path = public
AS $$
DECLARE
  w workouts;
BEGIN
  SELECT * INTO w FROM workouts WHERE id = p_workout_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF auth.uid() IS DISTINCT FROM w.user_id AND auth.uid() IS DISTINCT FROM w.buddy_id THEN
    RAISE EXCEPTION 'not_participant';
  END IF;
  RETURN w;
END;
$$;
REVOKE EXECUTE ON FUNCTION public._hs_lock(uuid) FROM PUBLIC, anon, authenticated;

-- One workout as the card sees it, from p_uid's side. The state is derived
-- here so the client has no state logic.
CREATE FUNCTION public._workout_card_json(w public.workouts, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path = public
AS $$
DECLARE
  v_me_creator boolean := p_uid = w.user_id;
  v_other uuid := CASE WHEN p_uid = w.user_id THEN w.buddy_id ELSE w.user_id END;
  v_mine boolean := (CASE WHEN p_uid = w.user_id THEN w.creator_ready ELSE w.buddy_ready END) IS TRUE;
  v_theirs boolean := (CASE WHEN p_uid = w.user_id THEN w.buddy_ready ELSE w.creator_ready END) IS TRUE;
  v_i_left boolean := (CASE WHEN p_uid = w.user_id THEN w.creator_cancelled ELSE w.buddy_cancelled END) IS TRUE;
  v_goal integer := LEAST(GREATEST(COALESCE(w.planned_duration_minutes, 30), 15), 210);
  v_state text;
  p record;
BEGIN
  v_state := CASE
    WHEN w.status IN ('completed', 'cancelled') OR v_i_left
      OR (w.status = 'scheduled' AND now() > w.planned_at + interval '15 minutes') THEN 'closed'
    WHEN w.status = 'in_progress' THEN
      CASE WHEN now() >= w.workout_started_at + make_interval(mins => v_goal) THEN 'goal_reached'
           WHEN w.buddy_id IS NULL THEN 'solo'
           ELSE 'running' END
    WHEN w.buddy_id IS NOT NULL AND w.buddy_cancelled IS TRUE THEN 'buddy_cant_make_it'
    WHEN (w.buddy_id IS NOT NULL AND w.buddy_status IS DISTINCT FROM 'accepted')
      OR now() < w.planned_at - interval '5 minutes' THEN 'waiting_start_time'
    WHEN v_mine THEN 'i_am_here'
    WHEN v_theirs THEN 'buddy_is_here'
    ELSE 'time_to_start'
  END;

  SELECT up.id, up.display_name, up.avatar_id, up.avatar_border,
         (SELECT si.color_hex FROM user_inventory ui JOIN shop_items si ON si.id = ui.shop_item_id
          WHERE ui.user_id = up.id AND ui.equipped AND si.category = 'ring_color' LIMIT 1) AS ring_color
  INTO p FROM user_profiles up WHERE up.id = v_other;

  -- jsonb orders keys by length, so no key is shorter than 'state'.
  RETURN jsonb_build_object(
    'state', v_state,
    'workout_id', w.id,
    'workout_type', w.workout_type,
    'status', w.status,
    'buddy_status', w.buddy_status,
    'closed_reason', w.closed_reason,
    'i_am_creator', v_me_creator,
    'planned_at', w.planned_at,
    'window_opens_at', w.planned_at - interval '5 minutes',
    'expires_at', w.planned_at + interval '15 minutes',
    'planned_duration_minutes', w.planned_duration_minutes,
    'workout_started_at', w.workout_started_at,
    'goal_at', w.workout_started_at + make_interval(mins => v_goal),
    'creator_ready', w.creator_ready IS TRUE,
    'buddy_ready', w.buddy_ready IS TRUE,
    'creator_cancelled', w.creator_cancelled IS TRUE,
    'buddy_cancelled', w.buddy_cancelled IS TRUE,
    'last_nudge_at', w.last_nudge_at,
    'other_person', CASE WHEN v_other IS NULL THEN NULL ELSE jsonb_build_object(
      'id', p.id, 'display_name', p.display_name, 'avatar_id', p.avatar_id,
      'avatar_border', p.avatar_border, 'ring_color', p.ring_color) END);
END;
$$;
REVOKE EXECUTE ON FUNCTION public._workout_card_json(public.workouts, uuid) FROM PUBLIC, anon, authenticated;

-- ── RPCs ────────────────────────────────────────────────────────────────
CREATE FUNCTION public.accept_workout_invite(p_workout_id uuid, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
  o record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  IF v_uid IS DISTINCT FROM w.buddy_id THEN RAISE EXCEPTION 'not_invitee'; END IF;
  IF w.status = 'scheduled' AND w.buddy_status = 'accepted' THEN
    RETURN jsonb_build_object('state', 'accepted');
  END IF;
  IF w.status <> 'scheduled' OR w.buddy_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;
  IF now() > w.planned_at + interval '15 minutes' THEN RAISE EXCEPTION 'window_closed'; END IF;

  -- Another workout the invitee is already committed to, overlapping
  -- [planned_at, planned_at + duration).
  IF NOT p_force THEN
    SELECT x.id, x.planned_at, COALESCE(up.display_name, x.workout_type) AS name INTO o
    FROM workouts x
    LEFT JOIN user_profiles up
      ON up.id = CASE WHEN x.user_id = v_uid THEN x.buddy_id ELSE x.user_id END
    WHERE x.id <> w.id
      AND ((x.user_id = v_uid AND x.creator_cancelled IS NOT TRUE)
        OR (x.buddy_id = v_uid AND x.buddy_status = 'accepted' AND x.buddy_cancelled IS NOT TRUE))
      AND (x.status = 'in_progress'
        OR (x.status = 'scheduled' AND x.planned_at + interval '15 minutes' >= now()))
      AND tstzrange(COALESCE(x.workout_started_at, x.planned_at),
                    COALESCE(x.workout_started_at, x.planned_at)
                      + make_interval(mins => COALESCE(x.planned_duration_minutes, 60)))
       && tstzrange(w.planned_at, w.planned_at + make_interval(mins => COALESCE(w.planned_duration_minutes, 60)))
    ORDER BY x.planned_at
    LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object('state', 'overlap', 'with_workout_id', o.id,
                                'with_name', o.name, 'with_planned_at', o.planned_at);
    END IF;
  END IF;

  UPDATE workouts SET buddy_status = 'accepted', updated_at = now() WHERE id = w.id;
  RETURN jsonb_build_object('state', 'accepted');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.accept_workout_invite(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.accept_workout_invite(uuid, boolean) TO authenticated;

CREATE FUNCTION public.decline_workout_invite(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  IF v_uid IS DISTINCT FROM w.buddy_id THEN RAISE EXCEPTION 'not_invitee'; END IF;
  IF w.buddy_status = 'declined' THEN RETURN jsonb_build_object('state', 'closed'); END IF;
  IF w.status <> 'scheduled' OR w.buddy_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;
  UPDATE workouts
  SET buddy_status = 'declined', status = 'cancelled', closed_reason = 'declined', updated_at = now()
  WHERE id = w.id;
  RETURN jsonb_build_object('state', 'closed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.decline_workout_invite(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.decline_workout_invite(uuid) TO authenticated;

-- "I'm here": either person, either order. The second tap (or a solo tap)
-- starts the workout on the server clock and opens both sessions, pinned to
-- that start (mirrors WorkoutService.setBuddyReady).
CREATE FUNCTION public.im_here(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
  v_me_creator boolean;
  v_start timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  v_me_creator := v_uid = w.user_id;

  IF w.status = 'in_progress'
     AND (CASE WHEN v_me_creator THEN w.creator_ready ELSE w.buddy_ready END) IS TRUE THEN
    RETURN jsonb_build_object('state', 'started', 'started_at', w.workout_started_at);
  END IF;
  IF w.status <> 'scheduled'
     OR (w.buddy_id IS NOT NULL AND w.buddy_status IS DISTINCT FROM 'accepted')
     OR (CASE WHEN v_me_creator THEN w.creator_cancelled ELSE w.buddy_cancelled END) IS TRUE THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;
  IF now() < w.planned_at - interval '5 minutes' THEN RAISE EXCEPTION 'too_early'; END IF;
  IF now() > w.planned_at + interval '15 minutes' THEN RAISE EXCEPTION 'window_closed'; END IF;

  IF v_me_creator THEN
    UPDATE workouts SET creator_ready = true, updated_at = now() WHERE id = w.id;
    w.creator_ready := true;
  ELSE
    UPDATE workouts SET buddy_ready = true, updated_at = now() WHERE id = w.id;
    w.buddy_ready := true;
  END IF;

  IF w.buddy_id IS NOT NULL
     AND NOT (w.creator_ready IS TRUE AND w.buddy_ready IS TRUE
              AND w.creator_cancelled IS NOT TRUE AND w.buddy_cancelled IS NOT TRUE) THEN
    RETURN jsonb_build_object('state', 'waiting_for_buddy');
  END IF;

  IF EXISTS (SELECT 1 FROM active_checkin_sessions s
             WHERE s.user_id IN (w.user_id, w.buddy_id) AND s.workout_id IS DISTINCT FROM w.id) THEN
    RAISE EXCEPTION 'already_in_workout';
  END IF;

  v_start := now();
  -- creator_joined keeps the installed app's card off its legacy join window.
  UPDATE workouts
  SET status = 'in_progress', workout_started_at = v_start, started_by_user_id = v_uid,
      creator_joined = true, updated_at = v_start
  WHERE id = w.id;

  INSERT INTO active_checkin_sessions
    (user_id, started_at, planned_duration, workout_type, workout_emoji, workout_id)
  SELECT u, v_start, COALESCE(w.planned_duration_minutes, 30), w.workout_type,
         CASE lower(w.workout_type)
           WHEN 'cardio' THEN '🏃' WHEN 'strength' THEN '💪' WHEN 'hiit' THEN '⚡'
           WHEN 'leg day' THEN '🦵' WHEN 'lower body' THEN '🦵' WHEN 'upper body' THEN '💪'
           WHEN 'full body' THEN '🏋️' WHEN 'yoga' THEN '🧘' ELSE '🏋️' END,
         w.id
  FROM unnest(ARRAY[w.user_id, w.buddy_id]) AS u
  WHERE u IS NOT NULL
  ON CONFLICT (user_id) DO UPDATE SET
    started_at = EXCLUDED.started_at, planned_duration = EXCLUDED.planned_duration,
    workout_type = EXCLUDED.workout_type, workout_emoji = EXCLUDED.workout_emoji,
    workout_id = EXCLUDED.workout_id;

  RETURN jsonb_build_object('state', 'started', 'started_at', v_start);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.im_here(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.im_here(uuid) TO authenticated;

-- The invitee backs out of an accepted workout. No penalty; the inviter
-- then chooses go_solo or cancel_workout.
CREATE FUNCTION public.cant_make_it(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  IF v_uid IS DISTINCT FROM w.buddy_id THEN RAISE EXCEPTION 'not_invitee'; END IF;
  IF w.status = 'scheduled' AND w.buddy_cancelled IS TRUE THEN
    RETURN jsonb_build_object('state', 'closed');
  END IF;
  IF w.status <> 'scheduled' OR w.buddy_status IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;
  UPDATE workouts SET buddy_cancelled = true, buddy_ready = false, updated_at = now() WHERE id = w.id;
  RETURN jsonb_build_object('state', 'closed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.cant_make_it(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cant_make_it(uuid) TO authenticated;

CREATE FUNCTION public.go_solo(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  IF v_uid IS DISTINCT FROM w.user_id THEN RAISE EXCEPTION 'not_creator'; END IF;
  IF w.buddy_id IS NULL AND w.status = 'scheduled' THEN
    RETURN jsonb_build_object('state', 'solo');
  END IF;
  IF NOT ((w.status = 'scheduled' AND w.buddy_cancelled IS TRUE)
       OR (w.status = 'cancelled' AND w.closed_reason IN ('declined', 'expired')
           AND now() <= w.planned_at + interval '15 minutes')) THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;
  UPDATE workouts
  SET buddy_id = NULL, buddy_status = 'pending', buddy_ready = false, buddy_cancelled = false,
      buddy_completed_at = NULL, status = 'scheduled', closed_reason = NULL,
      last_nudge_at = NULL, updated_at = now()
  WHERE id = w.id;
  RETURN jsonb_build_object('state', 'solo');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.go_solo(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.go_solo(uuid) TO authenticated;

CREATE FUNCTION public.cancel_workout(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  IF v_uid IS DISTINCT FROM w.user_id THEN RAISE EXCEPTION 'not_creator'; END IF;
  IF w.status = 'cancelled' AND w.closed_reason = 'cancelled_by_creator' THEN
    RETURN jsonb_build_object('state', 'closed');
  END IF;
  IF w.status <> 'scheduled' THEN RAISE EXCEPTION 'wrong_state'; END IF;
  UPDATE workouts
  SET status = 'cancelled', closed_reason = 'cancelled_by_creator', updated_at = now()
  WHERE id = w.id;
  RETURN jsonb_build_object('state', 'closed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.cancel_workout(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cancel_workout(uuid) TO authenticated;

-- Leaving a running workout: the caller's timer stops and they get no
-- credit (finish/auto-complete skip *_cancelled); the other keeps going.
CREATE FUNCTION public.leave_workout(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
  v_me_creator boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  v_me_creator := v_uid = w.user_id;
  IF (CASE WHEN v_me_creator THEN w.creator_cancelled ELSE w.buddy_cancelled END) IS TRUE THEN
    RETURN jsonb_build_object('state', CASE WHEN w.status = 'in_progress' THEN 'left' ELSE 'closed' END);
  END IF;
  IF w.status <> 'in_progress' THEN RAISE EXCEPTION 'wrong_state'; END IF;

  DELETE FROM active_checkin_sessions WHERE user_id = v_uid AND workout_id = w.id;

  IF w.buddy_id IS NULL THEN
    UPDATE workouts
    SET status = 'cancelled', creator_cancelled = true, closed_reason = 'solo_abandoned', updated_at = now()
    WHERE id = w.id;
    RETURN jsonb_build_object('state', 'closed');
  END IF;

  IF v_me_creator THEN
    UPDATE workouts SET creator_cancelled = true, updated_at = now() WHERE id = w.id;
  ELSE
    UPDATE workouts SET buddy_cancelled = true, updated_at = now() WHERE id = w.id;
  END IF;

  IF (CASE WHEN v_me_creator THEN w.buddy_cancelled ELSE w.creator_cancelled END) IS TRUE THEN
    UPDATE workouts SET status = 'cancelled', closed_reason = 'left' WHERE id = w.id;
    RETURN jsonb_build_object('state', 'closed');
  END IF;
  RETURN jsonb_build_object('state', 'left');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.leave_workout(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.leave_workout(uuid) TO authenticated;

-- Records the nudge only; H2 sends the push from a trigger on last_nudge_at.
CREATE FUNCTION public.nudge_workout(p_workout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
  v_me_creator boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  v_me_creator := v_uid = w.user_id;
  IF w.status <> 'scheduled' OR w.buddy_id IS NULL OR w.buddy_status IS DISTINCT FROM 'accepted'
     OR w.creator_cancelled IS TRUE OR w.buddy_cancelled IS TRUE
     OR (CASE WHEN v_me_creator THEN w.creator_ready ELSE w.buddy_ready END) IS NOT TRUE
     OR (CASE WHEN v_me_creator THEN w.buddy_ready ELSE w.creator_ready END) IS TRUE THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;
  IF now() < w.planned_at - interval '5 minutes' THEN RAISE EXCEPTION 'too_early'; END IF;
  IF now() > w.planned_at + interval '15 minutes' THEN RAISE EXCEPTION 'window_closed'; END IF;
  IF w.last_nudge_at > now() - interval '10 minutes' THEN
    RAISE EXCEPTION 'nudge_too_soon' USING DETAIL =
      ceil(extract(epoch FROM w.last_nudge_at + interval '10 minutes' - now()))::integer::text;
  END IF;
  UPDATE workouts SET last_nudge_at = now(), updated_at = now() WHERE id = w.id;
  RETURN jsonb_build_object('state', 'nudged', 'next_nudge_at', now() + interval '10 minutes');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.nudge_workout(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.nudge_workout(uuid) TO authenticated;

-- New time = new invite: the buddy has to accept again.
CREATE FUNCTION public.change_workout_time(p_workout_id uuid, p_date date, p_time time)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
  v_planned timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  IF v_uid IS DISTINCT FROM w.user_id THEN RAISE EXCEPTION 'not_creator'; END IF;
  IF w.status <> 'scheduled' THEN RAISE EXCEPTION 'wrong_state'; END IF;
  IF (p_date + p_time) AT TIME ZONE public.safe_user_tz(w.user_id) + interval '15 minutes' < now() THEN
    RAISE EXCEPTION 'window_closed';
  END IF;
  UPDATE workouts
  SET workout_date = p_date, workout_time = p_time, buddy_status = 'pending',
      creator_ready = false, buddy_ready = false, buddy_cancelled = false,
      last_nudge_at = NULL, updated_at = now()
  WHERE id = w.id
  RETURNING planned_at INTO v_planned;
  RETURN jsonb_build_object('state', 'rescheduled', 'planned_at', v_planned);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.change_workout_time(uuid, date, time) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.change_workout_time(uuid, date, time) TO authenticated;

-- Mirrors WorkoutService.completeWorkoutWithDuration. The client clamp
-- trigger skips definer calls, so its clamp is repeated here; the >= 15
-- floor and the 4/day cap triggers still fire. Credit stays in
-- finish_checkin_session.
CREATE FUNCTION public.complete_workout(p_workout_id uuid, p_actual_minutes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
  v_me_creator boolean;
  v_min integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  w := public._hs_lock(p_workout_id);
  v_me_creator := v_uid = w.user_id;
  IF (CASE WHEN v_me_creator THEN w.creator_cancelled ELSE w.buddy_cancelled END) IS TRUE THEN
    RAISE EXCEPTION 'wrong_state';
  END IF;

  IF w.status = 'completed' THEN
    IF NOT v_me_creator AND w.buddy_completed_at IS NULL THEN
      UPDATE workouts SET buddy_completed_at = now() WHERE id = w.id;
    END IF;
    DELETE FROM active_checkin_sessions WHERE user_id = v_uid;
    RETURN jsonb_build_object('state', 'completed', 'actual_minutes', w.actual_duration_minutes);
  END IF;
  IF w.status <> 'in_progress' THEN RAISE EXCEPTION 'wrong_state'; END IF;

  v_min := LEAST(
    COALESCE(p_actual_minutes, floor(extract(epoch FROM now() - w.workout_started_at) / 60)::integer),
    210,
    ceil(extract(epoch FROM now() - w.workout_started_at) / 60)::integer + 1);
  IF v_min IS NULL OR v_min < 15 THEN RAISE EXCEPTION 'too_early'; END IF;

  UPDATE workouts
  SET status = 'completed', actual_duration_minutes = v_min, workout_completed_at = now(),
      buddy_completed_at = CASE WHEN v_me_creator THEN buddy_completed_at ELSE now() END,
      closed_reason = 'completed', updated_at = now()
  WHERE id = w.id;
  DELETE FROM active_checkin_sessions WHERE user_id = v_uid;
  RETURN jsonb_build_object('state', 'completed', 'actual_minutes', v_min);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.complete_workout(uuid, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.complete_workout(uuid, integer) TO authenticated;

-- Read-only card data. Definer, so an invited friend's equipped ring colour
-- is readable without a shared active team streak (participants only).
CREATE FUNCTION public.get_workout_card(p_workout_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  w workouts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  IF p_workout_id IS NOT NULL THEN
    SELECT * INTO w FROM workouts WHERE id = p_workout_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
    IF v_uid IS DISTINCT FROM w.user_id AND v_uid IS DISTINCT FROM w.buddy_id THEN
      RAISE EXCEPTION 'not_participant';
    END IF;
  ELSE
    -- Current (running) first, else the next one still open for the caller.
    SELECT * INTO w FROM workouts x
    WHERE (x.user_id = v_uid OR (x.buddy_id = v_uid AND x.buddy_status = 'accepted'))
      AND (CASE WHEN x.user_id = v_uid THEN x.creator_cancelled ELSE x.buddy_cancelled END) IS NOT TRUE
      AND (x.status = 'in_progress'
        OR (x.status = 'scheduled' AND x.planned_at + interval '15 minutes' >= now()))
    ORDER BY (x.status = 'in_progress') DESC, x.planned_at
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'state', CASE WHEN w.id IS NULL THEN 'none' ELSE public._workout_card_json(w, v_uid)->>'state' END,
    'workout', CASE WHEN w.id IS NULL THEN NULL ELSE public._workout_card_json(w, v_uid) END,
    'invites', (SELECT COALESCE(jsonb_agg(public._workout_card_json(x, v_uid)
                  || jsonb_build_object('direction', CASE WHEN x.user_id = v_uid THEN 'sent' ELSE 'received' END)
                  ORDER BY x.created_at DESC), '[]'::jsonb)
                FROM workouts x
                WHERE (x.user_id = v_uid OR x.buddy_id = v_uid)
                  AND x.status = 'scheduled' AND x.buddy_status = 'pending' AND x.buddy_id IS NOT NULL
                  AND x.planned_at + interval '15 minutes' >= now()),
    'open_invite_count', (SELECT count(*) FROM workouts x
                          WHERE x.user_id = v_uid AND x.status = 'scheduled' AND x.buddy_status = 'pending'
                            AND x.buddy_id IS NOT NULL AND x.planned_at + interval '15 minutes' >= now()),
    'server_now', now());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_workout_card(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_workout_card(uuid) TO authenticated;

-- ── Expiry: pending or accepted-never-started, 15 min past planned_at ───
CREATE FUNCTION public.expire_stale_workout_invites()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_n integer;
BEGIN
  UPDATE workouts
  SET status = 'cancelled',
      buddy_status = CASE WHEN buddy_status = 'pending' THEN 'expired' ELSE buddy_status END,
      closed_reason = 'expired', updated_at = now()
  WHERE buddy_id IS NOT NULL AND status = 'scheduled'
    AND planned_at + interval '15 minutes' < now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.expire_stale_workout_invites() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.expire_stale_workout_invites() TO service_role;

SELECT cron.schedule('expire-stale-workout-invites', '*/5 * * * *',
                     'SELECT public.expire_stale_workout_invites();');

-- ── Realtime: workouts row changes on the private topic 'workouts' ──────
-- Which rows a subscriber receives is decided by the workouts SELECT RLS
-- (participants only). Join only, no INSERT policy: nobody can broadcast.
ALTER PUBLICATION supabase_realtime ADD TABLE public.workouts;

CREATE POLICY "authenticated can join workouts"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    (SELECT realtime.topic()) = 'workouts'
    AND realtime.messages.topic = 'workouts'
    AND realtime.messages.extension IN ('broadcast', 'presence')
  );
