-- Break declaration becomes server-authoritative: the weekly allowance is
-- checked atomically in declare_break_day(), and direct INSERT / reactivating
-- UPDATE paths on break_day_usage are closed. Cancelling stays client-side
-- (checkInAllTeams auto-cancel relies on it).

CREATE OR REPLACE FUNCTION public.declare_break_day()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_today      date;
  v_week_start date;
  v_max        integer;
  v_used       integer;
  v_row_id     uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  -- One declare at a time per user: closes the count-then-insert race.
  PERFORM pg_advisory_xact_lock(hashtext('break_day:' || v_uid::text));

  -- Server-computed, user's own local frame (same as all streak RPCs).
  v_today      := (now() AT TIME ZONE safe_user_tz(v_uid))::date;
  v_week_start := date_trunc('week', v_today)::date;  -- ISO Monday

  SELECT max_break_days INTO v_max
  FROM weekly_break_plans
  WHERE user_id = v_uid AND week_start_date = v_week_start;

  IF v_max IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'no_plan');
  END IF;

  SELECT count(*) INTO v_used
  FROM break_day_usage
  WHERE user_id = v_uid
    AND break_date BETWEEN v_week_start AND v_week_start + 6
    AND cancelled_at IS NULL;

  IF v_used >= v_max THEN
    RETURN jsonb_build_object('success', false, 'reason', 'limit_reached',
                              'used', v_used, 'max', v_max);
  END IF;

  -- Today only, date computed here -- the client never supplies one.
  -- Conflict with an ACTIVE row is a no-op (WHERE fails -> v_row_id NULL).
  INSERT INTO break_day_usage (user_id, break_date, declared_at, cancelled_at)
  VALUES (v_uid, v_today, now(), null)
  ON CONFLICT (user_id, break_date)
    DO UPDATE SET cancelled_at = null, declared_at = now()
    WHERE break_day_usage.cancelled_at IS NOT NULL
  RETURNING id INTO v_row_id;

  IF v_row_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_declared',
                              'used', v_used, 'max', v_max);
  END IF;

  RETURN jsonb_build_object('success', true, 'break_date', v_today,
                            'used', v_used + 1, 'max', v_max);
END;
$$;

REVOKE ALL ON FUNCTION public.declare_break_day() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.declare_break_day() TO authenticated;

-- Close the direct-write bypasses.
DROP POLICY "Users can insert their own break days" ON public.break_day_usage;

-- UPDATE may only ever cancel (new row must be cancelled) -- reactivation
-- has to go through declare_break_day where the cap is enforced.
DROP POLICY "Users can update their own break days" ON public.break_day_usage;
CREATE POLICY "Users can cancel their own break days"
  ON public.break_day_usage FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id AND cancelled_at IS NOT NULL);