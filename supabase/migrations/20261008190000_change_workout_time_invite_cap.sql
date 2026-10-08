-- H1 follow-up: change_workout_time turns an accepted invite back into a
-- pending one, so it must respect the 5-open-invites cap like an insert.
-- The row being changed is not counted (it is either already one of the
-- open invites or about to become one).
CREATE OR REPLACE FUNCTION public.change_workout_time(p_workout_id uuid, p_date date, p_time time)
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
  IF w.buddy_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('invite_cap:' || w.user_id::text));
    IF (SELECT count(*) FROM workouts
        WHERE user_id = w.user_id AND id <> w.id AND status = 'scheduled' AND buddy_status = 'pending'
          AND buddy_id IS NOT NULL AND planned_at + interval '15 minutes' >= now()) >= 5 THEN
      RAISE EXCEPTION 'invite_cap_reached';
    END IF;
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
