-- Rollback for 20261028230000_single_server_checkin. Restores the bodies dumped from live on 2026-10-28
-- (docs/hygiene/checkin_rpc_backup/) and drops the new functions. CREATE OR REPLACE keeps ACLs.
-- Pre-change ACLs (all SET search_path=public):
--   _server_checkin(uuid,date), _auto_credit(...), _apply_checkin_rewards, _fulfil_invite_reward,
--   notify_buddy_checkin, process_stale_sessions: {postgres=X/postgres,service_role=X/postgres}
--   finish_checkin_session(uuid), create_invite_team(uuid,uuid): {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   process_stale_sessions comment: NULL

CREATE OR REPLACE FUNCTION public._server_checkin(p_user_id uuid, p_day date)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  t record;
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- Same as BreakDayService.cancelBreakDay: working out cancels today's break.
  UPDATE break_day_usage SET cancelled_at = now()
  WHERE user_id = p_user_id AND break_date = p_day AND cancelled_at IS NULL;

  FOR t IN
    SELECT ts.id, bt.is_coach_max_team
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    JOIN buddy_teams bt ON bt.id = ts.team_id
    WHERE tm.user_id = p_user_id AND ts.is_active = true
  LOOP
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (t.id, p_user_id, p_day, now())
    ON CONFLICT (team_streak_id, user_id, check_in_date) DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    IF (public._recompute_team_streak(t.id, p_day)->>'updated')::boolean THEN
      PERFORM public._apply_checkin_rewards(p_user_id, t.id, p_day);
    END IF;

    IF t.is_coach_max_team AND NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = t.id AND user_id = v_coach_max_id AND check_in_date = p_day
    ) THEN
      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, p_day);
    END IF;
  END LOOP;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._server_checkin(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._server_checkin(uuid, date) TO service_role;

CREATE OR REPLACE FUNCTION public.finish_checkin_session(p_workout_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_tz text;
  v_start timestamptz;
  v_day date;
  v_level_before integer;
  v_level_after integer;
  v_on_break boolean;
  v_before jsonb;
  v_teams jsonb;
  v_checked_in integer;
  v_wk record;
  v_partner uuid;
  v_pday date;
  v_partner_before integer;
  v_partner_n integer := 0;
  v_sess_ok boolean := false;
  v_wk_ok boolean := false;
  v_sess_early boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_tz := public.safe_user_tz(v_uid);

  -- FIN-1: credit only (a) an eligible own session or (b) an eligible
  -- workout participation; anything else is a no-op that writes nothing.
  -- (a) own session: start pinned by the server, at least 15 minutes and at
  --     most 3h30 ago, and not tied to a workout the caller left or cancelled.
  --     Under 15 minutes it is too_early.
  SELECT COALESCE(w.workout_started_at, s.started_at),
         COALESCE(w.workout_started_at, s.started_at) BETWEEN now() - interval '210 minutes' AND now()
           AND NOT COALESCE(CASE WHEN v_uid = w.user_id THEN w.creator_cancelled ELSE w.buddy_cancelled END, false)
  INTO v_start, v_sess_ok
  FROM active_checkin_sessions s
  LEFT JOIN workouts w ON w.id = s.workout_id AND v_uid IN (w.user_id, w.buddy_id)
  WHERE s.user_id = v_uid
  FOR UPDATE OF s;
  v_sess_early := COALESCE(v_sess_ok AND v_start > now() - interval '15 minutes', false);
  v_sess_ok := COALESCE(v_sess_ok AND NOT v_sess_early, false);

  -- (b) participant of a started workout who has not left or cancelled, past
  --     the 15-minute floor: in progress and started within 3h30, or completed
  --     (by a person, not the cron) within 3h40 of its start (M3 grace),
  --     whenever Finish arrives; start day inside the reward window
  --     [today-1, today].
  IF p_workout_id IS NOT NULL THEN
    SELECT * INTO v_wk FROM workouts
    WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id)
      AND workout_started_at <= now()
      AND (workout_started_at AT TIME ZONE v_tz)::date >= (now() AT TIME ZONE v_tz)::date - 1
      AND CASE WHEN status = 'completed'
               THEN workout_completed_at <= workout_started_at + interval '220 minutes'
                    AND NOT COALESCE(auto_completed, false)
               ELSE workout_started_at >= now() - interval '210 minutes' END
      AND status IN ('in_progress', 'completed')
      AND NOT COALESCE(CASE WHEN v_uid = user_id THEN creator_cancelled ELSE buddy_cancelled END, false)
      AND CASE WHEN status = 'completed' THEN COALESCE(actual_duration_minutes, 0) >= 15
               ELSE now() - workout_started_at >= interval '15 minutes' END;
    v_wk_ok := FOUND;
  END IF;

  IF NOT (v_sess_ok OR v_wk_ok) THEN
    RETURN jsonb_build_object(
      'result', CASE WHEN v_sess_early THEN 'too_early' ELSE 'nothing_to_finish' END,
      'credit_date', (now() AT TIME ZONE v_tz)::date,
      'checked_in', 0, 'break_cancelled', false, 'did_level_up', false,
      'new_level', COALESCE((SELECT level FROM user_profiles WHERE id = v_uid), 1),
      'teams', '[]'::jsonb, 'partner_checked_in', 0);
  END IF;

  IF NOT v_sess_ok THEN
    v_start := v_wk.workout_started_at;
  END IF;
  v_day := (v_start AT TIME ZONE v_tz)::date;

  SELECT level INTO v_level_before FROM user_profiles WHERE id = v_uid;
  v_on_break := EXISTS (SELECT 1 FROM break_day_usage
                        WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL);
  SELECT jsonb_object_agg(ts.id, jsonb_build_object(
           'total', ts.total_workouts, 'best', ts.best_streak,
           'in', EXISTS (SELECT 1 FROM daily_team_checkins d
                         WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day)))
  INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  PERFORM public._server_checkin(v_uid, v_day);
  DELETE FROM active_checkin_sessions WHERE user_id = v_uid;

  -- M6a (owner rule 2026-10-02): in a buddy workout, the other participant
  -- who confirmed ready and has not cancelled is "in", session or not. Only
  -- when the caller is a participant and the workout started at most 3h30
  -- ago; credited to the partner's own local start day; idempotent through
  -- UNIQUE per team/user/day. Runs before the caller's results are read, so
  -- a shared streak the partner completes shows as advanced to the caller.
  -- FIN-1: only through a finisher eligible under (b) above, so a leaver
  -- never triggers it; v_wk is that workout (started, inside its window).
  IF v_wk_ok THEN
    IF v_wk.buddy_id IS NOT NULL AND v_wk.buddy_id <> v_wk.user_id THEN
      v_partner := CASE WHEN v_uid = v_wk.user_id THEN v_wk.buddy_id ELSE v_wk.user_id END;
      IF (v_partner = v_wk.user_id AND v_wk.creator_ready AND NOT v_wk.creator_cancelled)
         OR (v_partner = v_wk.buddy_id AND v_wk.buddy_ready AND NOT v_wk.buddy_cancelled) THEN
        v_pday := (v_wk.workout_started_at AT TIME ZONE public.safe_user_tz(v_partner))::date;
        SELECT count(*) INTO v_partner_before FROM daily_team_checkins
        WHERE user_id = v_partner AND check_in_date = v_pday;
        PERFORM public._server_checkin(v_partner, v_pday);
        DELETE FROM active_checkin_sessions WHERE user_id = v_partner AND workout_id = p_workout_id;
        SELECT count(*) - v_partner_before INTO v_partner_n FROM daily_team_checkins
        WHERE user_id = v_partner AND check_in_date = v_pday;
      END IF;
    END IF;
  END IF;

  SELECT level INTO v_level_after FROM user_profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'streak_id', ts.id, 'team_id', ts.team_id, 'is_coach_max_team', bt.is_coach_max_team,
           'updated', ts.total_workouts IS DISTINCT FROM (v_before->ts.id::text->>'total')::integer,
           'new_streak', ts.current_streak,
           'old_best_streak', COALESCE((v_before->ts.id::text->>'best')::integer, 0),
           'new_best_streak', ts.best_streak)), '[]'::jsonb),
         count(*) FILTER (WHERE NOT COALESCE((v_before->ts.id::text->>'in')::boolean, false)
                            AND EXISTS (SELECT 1 FROM daily_team_checkins d
                                        WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day))
  INTO v_teams, v_checked_in
  FROM team_streaks ts
  JOIN team_members tm ON tm.team_id = ts.team_id
  JOIN buddy_teams bt ON bt.id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  RETURN jsonb_build_object(
    'credit_date', v_day,
    'checked_in', v_checked_in,
    'break_cancelled', v_on_break AND NOT EXISTS (SELECT 1 FROM break_day_usage
                         WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL),
    'did_level_up', COALESCE(v_level_after, 1) > COALESCE(v_level_before, 1),
    'new_level', COALESCE(v_level_after, 1),
    'teams', v_teams,
    'partner_checked_in', v_partner_n);
END;
$function$;

CREATE OR REPLACE FUNCTION public._auto_credit(p_user uuid, p_start timestamp with time zone, p_goal integer, p_type text, p_emoji text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := (p_start AT TIME ZONE public.safe_user_tz(p_user))::date;
BEGIN
  IF EXISTS (SELECT 1 FROM workout_logs
             WHERE user_id = p_user AND auto_completed AND workout_date = v_day) THEN
    RETURN false;
  END IF;
  PERFORM public._server_checkin(p_user, v_day);
  INSERT INTO workout_logs (user_id, workout_date, workout_time, workout_name, workout_category,
                            workout_emoji, planned_duration_minutes, actual_duration_minutes, auto_completed)
  VALUES (p_user, v_day, p_start + make_interval(mins => p_goal), p_type,
          COALESCE((SELECT category FROM workout_templates WHERE name = p_type LIMIT 1), 'other'),
          COALESCE(p_emoji, '💪'), p_goal, p_goal, true);
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public._apply_checkin_rewards(p_user_id uuid, p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ref text := p_streak_id::text || ':' || p_check_in_date::text;
  v_current_streak integer;
  v_xp integer := 10;
  v_coins integer := 10;
  v_coop_xp integer := 5;
  v_coop_coins integer := 5;
  v_milestone_xp integer := 0;
  v_milestone_coins integer := 0;
  v_reasons jsonb := '[]'::jsonb;
  v_partner_checked_in boolean := false;
  v_teammate record;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_old_level integer;
  v_new_level integer;
  v_daily_cap_xp constant integer := 1000;
  v_daily_cap_coins constant integer := 100;
  v_already_xp integer;
  v_already_coins integer;
  v_capped boolean := false;
  v_user_tz text := public.safe_user_tz(p_user_id);
BEGIN
  -- One payout run per (streak, day) at a time, so the existence checks
  -- below cannot race a concurrent run for a teammate.
  PERFORM pg_advisory_xact_lock(hashtext('checkin_rewards:' || v_ref));

  IF EXISTS (
    SELECT 1 FROM xp_transactions
    WHERE user_id = p_user_id AND reference_id = v_ref
  ) THEN
    RETURN jsonb_build_object('already_awarded', true);
  END IF;

  SELECT level INTO v_old_level FROM user_profiles WHERE id = p_user_id;
  v_old_level := COALESCE(v_old_level, 1);

  SELECT current_streak INTO v_current_streak FROM team_streaks WHERE id = p_streak_id;
  v_current_streak := COALESCE(v_current_streak, 1);

  SELECT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id
      AND check_in_date = p_check_in_date
      AND user_id <> p_user_id
      AND user_id <> v_coach_max_id
  ) INTO v_partner_checked_in;

  IF v_partner_checked_in THEN
    v_xp := v_xp + v_coop_xp;
    v_coins := v_coins + v_coop_coins;
    v_reasons := v_reasons || jsonb_build_array('coop_bonus');
  END IF;

  -- Milestone amounts hoisted so the retro teammate loop can reuse them
  -- (same v_current_streak, same call -> symmetric by construction).
  IF v_current_streak = 7 THEN
    v_milestone_xp := 50; v_milestone_coins := 50;
    v_reasons := v_reasons || jsonb_build_array('milestone_7');
  ELSIF v_current_streak = 30 THEN
    v_milestone_xp := 50; v_milestone_coins := 100;
    v_reasons := v_reasons || jsonb_build_array('milestone_30');
  ELSIF v_current_streak = 100 THEN
    v_milestone_xp := 50; v_milestone_coins := 250;
    v_reasons := v_reasons || jsonb_build_array('milestone_100');
  END IF;
  v_xp := v_xp + v_milestone_xp;
  v_coins := v_coins + v_milestone_coins;

  -- Daily cap check for the primary user, in THEIR OWN local day (tz3_2)
  SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
  FROM xp_transactions
  WHERE user_id = p_user_id
    AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
    AND (created_at AT TIME ZONE v_user_tz)::date = p_check_in_date;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_coins
  FROM coin_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND (created_at AT TIME ZONE v_user_tz)::date = p_check_in_date;

  IF v_already_xp + v_xp > v_daily_cap_xp THEN
    v_xp := GREATEST(0, v_daily_cap_xp - v_already_xp);
    v_capped := true;
  END IF;
  IF v_already_coins + v_coins > v_daily_cap_coins THEN
    v_coins := GREATEST(0, v_daily_cap_coins - v_already_coins);
    v_capped := true;
  END IF;

  PERFORM award_xp(p_user_id, v_xp, 'daily_checkin', v_ref);
  PERFORM award_coins(p_user_id, v_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);

  SELECT level INTO v_new_level FROM user_profiles WHERE id = p_user_id;

  IF v_partner_checked_in THEN
    FOR v_teammate IN
      SELECT DISTINCT dtc.user_id
      FROM daily_team_checkins dtc
      WHERE dtc.team_streak_id = p_streak_id
        AND dtc.check_in_date = p_check_in_date
        AND dtc.user_id <> p_user_id
        AND dtc.user_id <> v_coach_max_id
    LOOP
      DECLARE
        -- Owed-checks: each entitlement deduped by its own kind + reference_id
        -- (XP rows carry the kind in description, coin rows in transaction_type).
        v_t_owed_base boolean;
        v_t_owed_coop boolean;
        v_t_already_xp integer;
        v_t_already_coins integer;
        v_t_base_xp integer := 0;
        v_t_base_coins integer := 0;
        v_t_coop_xp integer := 0;
        v_t_coop_coins integer := 0;
        v_t_room_xp integer;
        v_t_room_coins integer;
        -- Teammate's cap window is measured in the TEAMMATE's own local day.
        v_t_tz text := public.safe_user_tz(v_teammate.user_id);
      BEGIN
        v_t_owed_base := NOT EXISTS (
          SELECT 1 FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description = 'daily_checkin'
            AND reference_id = v_ref
        );
        v_t_owed_coop := NOT EXISTS (
          SELECT 1 FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'partner_bonus'
            AND reference_id = v_ref
        );

        IF v_t_owed_base OR v_t_owed_coop THEN
          -- 10/10 base matches the primary's v_xp/v_coins initialisers;
          -- milestone shares the hoisted amounts from this same call.
          IF v_t_owed_base THEN
            v_t_base_xp := 10 + v_milestone_xp;
            v_t_base_coins := 10 + v_milestone_coins;
          END IF;
          IF v_t_owed_coop THEN
            v_t_coop_xp := v_coop_xp;
            v_t_coop_coins := v_coop_coins;
          END IF;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
          FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
            AND (created_at AT TIME ZONE v_t_tz)::date = p_check_in_date;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_coins
          FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND (created_at AT TIME ZONE v_t_tz)::date = p_check_in_date;

          -- Cap the combined owed amount: base takes the remaining room
          -- first, co-op whatever is left after that.
          v_t_room_xp := GREATEST(0, v_daily_cap_xp - v_t_already_xp);
          v_t_room_coins := GREATEST(0, v_daily_cap_coins - v_t_already_coins);
          v_t_base_xp := LEAST(v_t_base_xp, v_t_room_xp);
          v_t_base_coins := LEAST(v_t_base_coins, v_t_room_coins);
          v_t_coop_xp := LEAST(v_t_coop_xp, v_t_room_xp - v_t_base_xp);
          v_t_coop_coins := LEAST(v_t_coop_coins, v_t_room_coins - v_t_base_coins);

          -- Award each owed part even when capped to 0: the ref-tagged txn
          -- is what marks the entitlement as covered for future dedup.
          IF v_t_owed_base THEN
            PERFORM award_xp(v_teammate.user_id, v_t_base_xp, 'daily_checkin', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_base_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);
          END IF;
          IF v_t_owed_coop THEN
            PERFORM award_xp(v_teammate.user_id, v_t_coop_xp, 'partner_bonus', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_coop_coins, 'partner_bonus', 'Partner checked in too!', v_ref);
          END IF;
        END IF;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'xp_awarded', v_xp,
    'coins_awarded', v_coins,
    'current_streak', v_current_streak,
    'reasons', v_reasons,
    'old_level', v_old_level,
    'new_level', v_new_level,
    'did_level_up', v_new_level > v_old_level,
    'daily_cap_reached', v_capped
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_buddy_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_other_user_id uuid;
  v_team_id uuid;
BEGIN
  SELECT team_id INTO v_team_id FROM team_streaks WHERE id = NEW.team_streak_id;
  IF v_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT tm.user_id INTO v_other_user_id
  FROM team_members tm
  WHERE tm.team_id = v_team_id
    AND tm.user_id != NEW.user_id
  LIMIT 1;

  PERFORM public._send_push(v_other_user_id, 'buddy_checked_in', '{}'::jsonb, 'emerald', 'streaks',
                            'buddy_checked_in', v_team_id::text, 'streak_' || v_team_id, false, NEW.user_id);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id UUID;
  v_invite_id UUID;
  v_invite_created TIMESTAMPTZ;
  v_invitee_is_new BOOLEAN;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT id, created_at INTO v_invite_id, v_invite_created
  FROM invites
  WHERE inviter_id = p_inviter_id
    AND accepted_by = p_invitee_id
    AND status = 'accepted'
  ORDER BY accepted_at DESC NULLS LAST
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  SELECT tm1.team_id INTO v_team_id
  FROM team_members tm1
  JOIN team_members tm2 ON tm2.team_id = tm1.team_id AND tm2.user_id = p_invitee_id
  WHERE tm1.user_id = p_inviter_id
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    RETURN v_team_id;
  END IF;

  INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by, created_at, updated_at)
  VALUES ('Gym Buddies', '💪', false, 2, p_inviter_id, v_now, v_now)
  RETURNING id INTO v_team_id;

  INSERT INTO team_members (team_id, user_id, role, joined_at, created_at)
  VALUES
    (v_team_id, p_inviter_id, 'member', v_now, v_now),
    (v_team_id, p_invitee_id, 'member', v_now, v_now);

  INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active, created_at, updated_at)
  VALUES (v_team_id, 0, 0, true, v_now, v_now);

  INSERT INTO friendships (user_id, friend_id, status)
  SELECT p_inviter_id, p_invitee_id, 'accepted'
  WHERE NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = p_inviter_id AND friend_id = p_invitee_id)
       OR (user_id = p_invitee_id AND friend_id = p_inviter_id)
  );

  SELECT (u.created_at > v_invite_created) INTO v_invitee_is_new
  FROM auth.users u WHERE u.id = p_invitee_id;

  IF COALESCE(v_invitee_is_new, false) THEN
    IF NOT EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_bonus'
        AND reference_id = v_invite_id::text
        AND user_id = p_invitee_id
    ) THEN
      PERFORM award_coins(p_invitee_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite_id::text);
    END IF;
  END IF;

  RETURN v_team_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public._fulfil_invite_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_invite  RECORD;
  v_days    INT;
  v_friends INT;
  v_amount  INT;
BEGIN
  FOR v_invite IN
    SELECT i.id, i.inviter_id, i.created_at
    FROM invites i
    WHERE i.accepted_by = NEW.user_id
      AND i.status = 'accepted'
    FOR UPDATE
  LOOP
    IF EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_reward'
        AND reference_id = v_invite.id::text
    ) THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = NEW.user_id
        AND u.created_at > v_invite.created_at
    ) THEN
      CONTINUE;
    END IF;

    SELECT COUNT(DISTINCT check_in_date) INTO v_days
    FROM daily_team_checkins
    WHERE user_id = NEW.user_id;

    IF v_days < 2 THEN
      CONTINUE;
    END IF;

    SELECT COUNT(*) INTO v_friends
    FROM friendships
    WHERE status = 'accepted'
      AND (user_id = v_invite.inviter_id OR friend_id = v_invite.inviter_id);

    v_amount := CASE
      WHEN v_friends < 30 THEN 20
      WHEN v_friends < 60 THEN 10
      WHEN v_friends < 90 THEN 5
      ELSE 2
    END;

    BEGIN
      PERFORM award_coins(
        v_invite.inviter_id, v_amount, 'invite_reward',
        'Buddy invite paid off', v_invite.id::text
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO invite_reward_dead_letters (invite_id, inviter_id, amount, error_message)
      VALUES (v_invite.id, v_invite.inviter_id, v_amount, SQLERRM);
    END;
  END LOOP;

  RETURN NULL;
END;
$function$;

DROP FUNCTION public.submit_checkin();
DROP FUNCTION public._credit_checkin(uuid, timestamp with time zone, boolean, timestamp with time zone, uuid);
DROP FUNCTION public._credit_day(uuid, timestamp with time zone);
COMMENT ON FUNCTION public.process_stale_sessions(timestamp with time zone) IS NULL;
