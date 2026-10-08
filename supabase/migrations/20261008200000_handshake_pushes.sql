-- H2: push wording in a table, one helper that sends, handshake pushes from
-- workouts transitions, time_to_start cron, existing push triggers moved to
-- the new copy. No emojis in any push text.

-- ── Templates (service / definer only) ──────────────────────────────────
CREATE TABLE public.push_templates (
  key text NOT NULL,
  variant integer NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  PRIMARY KEY (key, variant)
);
ALTER TABLE public.push_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_templates FROM anon, authenticated;

INSERT INTO public.push_templates (key, variant, title, body) VALUES
  ('invite_received', 1, '{name}', 'wants a training partner. {type}, {time}.'),
  ('invite_received', 2, '{name}', 'invited you to {type} at {time}. In or out?'),
  ('invite_accepted', 1, '{name}', 'is in. {type} at {time} is on.'),
  ('invite_accepted', 2, '{name}', 'said yes. See you at {time}.'),
  ('invite_declined', 1, '{name}', 'passed. Your {time} is open, go solo or ask someone else.'),
  ('invite_expired', 1, '{name}', 'never answered. The {time} invite expired.'),
  ('invite_rescheduled', 1, '{name}', 'moved {type} to {time}. Still in?'),
  ('workout_cancelled', 1, '{name}', 'cancelled {type} at {time}. No penalty.'),
  ('time_to_start', 1, '{type} with {name}', 'It''s {time}. Tap I''m here.'),
  ('time_to_start', 2, '{name}', 'is probably waiting. Tap I''m here.'),
  ('time_to_start', 3, 'Showtime', '{type} with {name} starts now. Tap I''m here.'),
  ('buddy_tapped_first', 1, '{name}{streak}', 'is here. Your move.'),
  ('buddy_tapped_first', 2, '{name}', 'is already warmed up. Tap I''m here to start the timer.'),
  ('started', 1, 'Clock''s running', '{name} is in. {minutes} minutes, no excuses.'),
  ('nudge', 1, '{name}', 'is already here. Your move.'),
  ('nudge', 2, 'Ready when you are', '{name} tapped in. Tap I''m here to start.'),
  ('nudge', 3, '{name}', 'is waiting. Tap I''m here, the timer won''t start itself.'),
  ('cant_make_it', 1, '{name}', 'is out today. No penalty, go solo and your streak lives.'),
  ('buddy_left', 1, '{name}', 'left the workout. Your timer keeps going. Finish to count it.'),
  ('buddy_finished', 1, '{name}{streak}', 'is done. Your turn.'),
  ('still_going', 1, 'Still going?', 'You''re past your goal. Tap Finish when you''re done.'),
  ('before_auto', 1, 'Your workout is still running', '3 hours in. Tap Finish so the time is exact.'),
  ('friend_request', 1, '{name}', 'wants to be your gym buddy. Accept to start a streak together.'),
  ('friend_accepted', 1, '{name}', 'is your buddy now. Pick a time and train.'),
  ('streak_milestone', 1, 'Day {n} with {team}', 'You both showed up.'),
  ('streak_broken', 1, 'Streak ended', '{n} days with {team}. Start the next one today.'),
  ('buddy_checked_in', 1, '{name}{streak}', 'is done. Your turn.'),
  ('buddy_nudge', 1, '{name}', 'is waiting on your check-in. Keep it going.'),
  ('streak_danger', 1, 'Streak in danger', 'Your {n}-day streak ends at midnight. Check in now.'),
  ('streak_danger_first', 1, 'Streak in danger', 'Don''t lose your first streak day. Check in before midnight.'),
  -- Coach Max: the existing lines, emojis removed, nothing else changed.
  ('coach_max_day1', 1, 'Coach Max', 'Day 1 starts now! Let''s build something great!'),
  ('coach_max_day1', 2, 'Coach Max', 'Every champion started somewhere. Today is your day!'),
  ('coach_max_day1', 3, 'Coach Max', 'Ready to begin? Let''s go!'),
  ('coach_max_legend', 1, 'Coach Max', '{n} DAYS! You''re a legend!'),
  ('coach_max_legend', 2, 'Coach Max', 'This {n}-day streak is INSANE! Keep it alive!'),
  ('coach_max_legend', 3, 'Coach Max', 'Champion mentality! {n} days strong!'),
  ('coach_max_strong', 1, 'Coach Max', '{n} days strong! You''re building something special!'),
  ('coach_max_strong', 2, 'Coach Max', 'Look at that {n}-day streak! Consistency is key!'),
  ('coach_max_strong', 3, 'Coach Max', '{n} consecutive days! You''re on fire!'),
  ('coach_max_daily', 1, 'Coach Max', 'Ready to work? Let''s do this!'),
  ('coach_max_daily', 2, 'Coach Max', 'Another day, another opportunity! Let''s go!'),
  ('coach_max_daily', 3, 'Coach Max', 'Day {next} awaits! Let''s make it count!'),
  ('coach_max_daily', 4, 'Coach Max', 'Keep the momentum going!');

-- ── _send_push: one random variant, variables filled, sent like the
-- existing triggers (pg_net → send-notification, service role) ─────────
-- Variables: {name} first name of p_sender, {streak} ' · Day N' for the
-- shared active streak (empty when none), {time} HH24:MI of
-- p_vars->>'planned_at' in the RECIPIENT's zone; any other {x} from p_vars.
-- Skips (returns false) when there is no recipient, no token or no template.
CREATE FUNCTION public._send_push(
  p_user uuid, p_key text, p_vars jsonb, p_kind text, p_channel text, p_type text,
  p_ref text, p_tag text, p_urgent boolean DEFAULT false, p_sender uuid DEFAULT NULL)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  t record;
  s record;
  v_streak integer;
  v_vars jsonb;
  v_title text;
  v_body text;
  k text;
  v text;
  v_service_key text;
BEGIN
  IF p_user IS NULL OR NOT EXISTS (SELECT 1 FROM device_tokens WHERE user_id = p_user) THEN
    RETURN false;
  END IF;
  SELECT title, body INTO t FROM push_templates WHERE key = p_key ORDER BY random() LIMIT 1;
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT up.display_name, up.username, up.avatar_id, up.avatar_border,
         (SELECT si.color_hex FROM user_inventory ui JOIN shop_items si ON si.id = ui.shop_item_id
          WHERE ui.user_id = up.id AND ui.equipped AND si.category = 'ring_color' LIMIT 1) AS ring_hex
  INTO s FROM user_profiles up WHERE up.id = p_sender;

  SELECT max(ts.current_streak) INTO v_streak
  FROM team_streaks ts
  JOIN team_members a ON a.team_id = ts.team_id AND a.user_id = p_user
  JOIN team_members b ON b.team_id = ts.team_id AND b.user_id = p_sender
  WHERE ts.is_active;

  v_vars := jsonb_build_object(
      'name', COALESCE(NULLIF(split_part(btrim(COALESCE(s.display_name, s.username, '')), ' ', 1), ''), 'Your buddy'),
      'streak', CASE WHEN v_streak > 0 THEN ' · Day ' || v_streak ELSE '' END)
    || COALESCE(p_vars, '{}'::jsonb);
  IF p_vars ? 'planned_at' THEN
    v_vars := v_vars || jsonb_build_object('time',
      to_char((p_vars->>'planned_at')::timestamptz AT TIME ZONE public.safe_user_tz(p_user), 'HH24:MI'));
  END IF;

  v_title := t.title;
  v_body := t.body;
  FOR k, v IN SELECT * FROM jsonb_each_text(v_vars) LOOP
    v_title := replace(v_title, '{' || k || '}', COALESCE(v, ''));
    v_body := replace(v_body, '{' || k || '}', COALESCE(v, ''));
  END LOOP;
  v_title := regexp_replace(v_title, '\{[a-z_]+\}', '', 'g');
  v_body := regexp_replace(v_body, '\{[a-z_]+\}', '', 'g');

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'user_id', p_user,
      'title', v_title,
      'body', v_body,
      'type', p_type,
      'reference_id', p_ref,
      'kind', p_kind,
      'color', CASE p_kind
                 WHEN 'orange' THEN '#EA580C' WHEN 'lavender' THEN '#A99BF5'
                 WHEN 'emerald' THEN '#50C878' WHEN 'amber' THEN '#FBBF24'
                 WHEN 'red' THEN '#F87171' ELSE '#B9CFC3' END,
      'channel', 'gym_buddy_' || p_channel,
      'tag', p_tag,
      'urgent', p_urgent,
      'batch_key', p_key || '_' || COALESCE(p_ref, ''),
      'dedupe_minutes', CASE p_key WHEN 'nudge' THEN 10 WHEN 'time_to_start' THEN 120
                          ELSE CASE WHEN p_channel IN ('handshake', 'invites') THEN 1 ELSE 60 END END,
      'data', jsonb_build_object(
        'avatar_id', s.avatar_id,
        'avatar_border', s.avatar_border,
        'ring_hex', s.ring_hex,
        'sender_name', CASE WHEN p_sender IS NULL THEN NULL ELSE v_vars->>'name' END,
        'streak', COALESCE(v_streak::text, '')))
  );
  RETURN true;
END;
$$;
REVOKE EXECUTE ON FUNCTION public._send_push(uuid, text, jsonb, text, text, text, text, text, boolean, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._send_push(uuid, text, jsonb, text, text, text, text, text, boolean, uuid)
  TO service_role;

-- ── Handshake pushes from workouts transitions ──────────────────────────
-- Recipient skipped when null, the actor, or has left / can't make it.
ALTER TABLE public.workouts
  ADD COLUMN time_to_start_sent_at timestamptz,
  ADD COLUMN before_auto_sent_at timestamptz;

CREATE FUNCTION public.notify_workout_handshake()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_vars jsonb := jsonb_build_object('type', NEW.workout_type, 'planned_at', NEW.planned_at,
                                     'minutes', COALESCE(NEW.planned_duration_minutes, 30));
  v_ready uuid;
  q jsonb := '[]'::jsonb;  -- [to, from, key, kind, channel, tag, urgent]
  p jsonb;
  v_to uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    q := q || jsonb_build_array(jsonb_build_array(NEW.buddy_id, NEW.user_id, 'invite_received', 'lavender', 'invites', 'invite_' || NEW.id, false));
  ELSE
    IF OLD.buddy_status = 'pending' AND NEW.buddy_status IN ('accepted', 'declined', 'expired') THEN
      q := q || jsonb_build_array(jsonb_build_array(NEW.user_id, NEW.buddy_id, 'invite_' || NEW.buddy_status,
        CASE WHEN NEW.buddy_status = 'accepted' THEN 'lavender' ELSE 'grey' END, 'invites', 'invite_' || NEW.id, false));
    END IF;
    IF NEW.status = 'scheduled' AND NEW.planned_at IS DISTINCT FROM OLD.planned_at THEN
      q := q || jsonb_build_array(jsonb_build_array(NEW.buddy_id, NEW.user_id, 'invite_rescheduled', 'lavender', 'invites', 'invite_' || NEW.id, false));
    END IF;
    IF NEW.closed_reason = 'cancelled_by_creator' AND OLD.closed_reason IS DISTINCT FROM 'cancelled_by_creator' THEN
      q := q || jsonb_build_array(jsonb_build_array(NEW.buddy_id, NEW.user_id, 'workout_cancelled', 'red', 'handshake', 'hs_' || NEW.id, false));
    END IF;
    IF NEW.status = 'scheduled' AND NEW.buddy_cancelled IS TRUE AND OLD.buddy_cancelled IS NOT TRUE THEN
      q := q || jsonb_build_array(jsonb_build_array(NEW.user_id, NEW.buddy_id, 'cant_make_it', 'grey', 'handshake', 'hs_' || NEW.id, false));
    END IF;
    IF NEW.status = 'scheduled' AND OLD.creator_ready IS NOT TRUE AND OLD.buddy_ready IS NOT TRUE
       AND (NEW.creator_ready IS TRUE) <> (NEW.buddy_ready IS TRUE) THEN
      v_ready := CASE WHEN NEW.creator_ready IS TRUE THEN NEW.user_id ELSE NEW.buddy_id END;
      q := q || jsonb_build_array(jsonb_build_array(
        CASE WHEN v_ready = NEW.user_id THEN NEW.buddy_id ELSE NEW.user_id END, v_ready,
        'buddy_tapped_first', 'orange', 'handshake', 'hs_' || NEW.id, true));
    END IF;
    IF NEW.status = 'in_progress' AND OLD.status IS DISTINCT FROM 'in_progress' THEN
      q := q || jsonb_build_array(jsonb_build_array(
        CASE WHEN NEW.started_by_user_id = NEW.user_id THEN NEW.buddy_id ELSE NEW.user_id END, NEW.started_by_user_id,
        'started', 'emerald', 'handshake', 'hs_' || NEW.id, true));
    END IF;
    IF NEW.last_nudge_at IS DISTINCT FROM OLD.last_nudge_at AND NEW.last_nudge_at IS NOT NULL THEN
      q := q || jsonb_build_array(jsonb_build_array(
        CASE WHEN NEW.creator_ready IS TRUE THEN NEW.buddy_id ELSE NEW.user_id END,
        CASE WHEN NEW.creator_ready IS TRUE THEN NEW.user_id ELSE NEW.buddy_id END,
        'nudge', 'orange', 'handshake', 'nudge_' || NEW.id, true));
    END IF;
    IF OLD.status = 'in_progress' AND NEW.creator_cancelled IS TRUE AND OLD.creator_cancelled IS NOT TRUE THEN
      q := q || jsonb_build_array(jsonb_build_array(NEW.buddy_id, NEW.user_id, 'buddy_left', 'grey', 'handshake', 'run_' || NEW.id, false));
    END IF;
    IF OLD.status = 'in_progress' AND NEW.buddy_cancelled IS TRUE AND OLD.buddy_cancelled IS NOT TRUE THEN
      q := q || jsonb_build_array(jsonb_build_array(NEW.user_id, NEW.buddy_id, 'buddy_left', 'grey', 'handshake', 'run_' || NEW.id, false));
    END IF;
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed'
       AND NEW.auto_completed IS NOT TRUE AND v_actor IS NOT NULL THEN
      q := q || jsonb_build_array(jsonb_build_array(
        CASE WHEN v_actor = NEW.user_id THEN NEW.buddy_id ELSE NEW.user_id END, v_actor,
        'buddy_finished', 'emerald', 'handshake', 'run_' || NEW.id, false));
    END IF;
  END IF;

  IF NEW.buddy_id IS NULL THEN RETURN NULL; END IF;  -- solo: no handshake pushes
  FOR p IN SELECT * FROM jsonb_array_elements(q) LOOP
    v_to := (p->>0)::uuid;
    CONTINUE WHEN v_to IS NULL OR v_to IS NOT DISTINCT FROM v_actor
      OR (v_to = NEW.user_id AND NEW.creator_cancelled IS TRUE)
      OR (v_to = NEW.buddy_id AND NEW.buddy_cancelled IS TRUE);
    PERFORM public._send_push(v_to, p->>2, v_vars, p->>3, p->>4, p->>2, NEW.id::text, p->>5,
                              (p->>6)::boolean, (p->>1)::uuid);
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.notify_workout_handshake() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER notify_workout_handshake
  AFTER INSERT OR UPDATE ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public.notify_workout_handshake();

-- ── time_to_start: once per accepted buddy workout, at planned_at ───────
-- Skips anyone who already tapped I'm here and rows where someone is out.
CREATE FUNCTION public.send_time_to_start_pushes()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  w record;
  v_vars jsonb;
  v_n integer := 0;
BEGIN
  FOR w IN
    SELECT * FROM workouts
    WHERE status = 'scheduled' AND buddy_id IS NOT NULL AND buddy_status = 'accepted'
      AND time_to_start_sent_at IS NULL
      AND planned_at <= now() AND planned_at + interval '15 minutes' >= now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE workouts SET time_to_start_sent_at = now() WHERE id = w.id;
    CONTINUE WHEN w.creator_cancelled IS TRUE OR w.buddy_cancelled IS TRUE;
    v_vars := jsonb_build_object('type', w.workout_type, 'planned_at', w.planned_at);
    IF w.creator_ready IS NOT TRUE THEN
      PERFORM public._send_push(w.user_id, 'time_to_start', v_vars, 'orange', 'handshake', 'time_to_start',
                                w.id::text, 'hs_' || w.id, true, w.buddy_id);
    END IF;
    IF w.buddy_ready IS NOT TRUE THEN
      PERFORM public._send_push(w.buddy_id, 'time_to_start', v_vars, 'orange', 'handshake', 'time_to_start',
                                w.id::text, 'hs_' || w.id, true, w.user_id);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_time_to_start_pushes() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.send_time_to_start_pushes() TO service_role;

SELECT cron.schedule('handshake-time-to-start', '* * * * *', 'SELECT public.send_time_to_start_pushes();');

-- ── Existing push triggers on the new copy (same events, same recipients) ─
CREATE OR REPLACE FUNCTION public.notify_friend_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  PERFORM public._send_push(NEW.friend_id, 'friend_request', '{}'::jsonb, 'lavender', 'friends',
                            'friend_request', NEW.id::text, 'friend_' || NEW.id, false, NEW.user_id);
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.notify_friend_request() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_friend_accepted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    PERFORM public._send_push(NEW.user_id, 'friend_accepted', '{}'::jsonb, 'lavender', 'friends',
                              'friend_accepted', NEW.id::text, 'friend_' || NEW.id, false, NEW.friend_id);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.notify_friend_accepted() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_buddy_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
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
$$;
REVOKE EXECUTE ON FUNCTION public.notify_buddy_checkin() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_streak_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE
  v_member uuid;
  v_team_name text;
BEGIN
  SELECT COALESCE(team_name, 'your buddy') INTO v_team_name FROM buddy_teams WHERE id = NEW.team_id;

  IF NEW.current_streak = 0 AND OLD.current_streak > 0 THEN
    FOR v_member IN SELECT user_id FROM team_members WHERE team_id = NEW.team_id LOOP
      PERFORM public._send_push(v_member, 'streak_broken',
        jsonb_build_object('n', OLD.current_streak, 'team', v_team_name), 'red', 'streaks',
        'streak_broken', NEW.id::text, 'streak_' || NEW.team_id, false, NULL);
    END LOOP;
  ELSIF NEW.current_streak != OLD.current_streak AND NEW.current_streak IN (7, 14, 30, 50, 100) THEN
    FOR v_member IN SELECT user_id FROM team_members WHERE team_id = NEW.team_id LOOP
      PERFORM public._send_push(v_member, 'streak_milestone',
        jsonb_build_object('n', NEW.current_streak, 'team', v_team_name), 'emerald', 'streaks',
        'streak_milestone', NEW.id::text, 'streak_' || NEW.team_id, false, NULL);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.notify_streak_update() FROM PUBLIC, anon, authenticated;

-- ── process_stale_sessions: pushes #8 ("Workout complete") and #9
-- ("Workout waiting") removed; the goal/reminder bookkeeping, crediting and
-- closing are unchanged (the old body minus the net.http_post block). ────
CREATE OR REPLACE FUNCTION public.process_stale_sessions(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key text;
  v_ids uuid[];
  v_sid uuid;
  s record;
  c record;
  v_credit uuid[];
  v_close boolean;
  v_any boolean;
  v_day date;
  v_kind text;
  v_title text;
  v_body text;
  v_pushed integer := 0;
  v_paid integer := 0;
  v_unpaid integer := 0;
  v_stale integer := 0;
  v_orphans integer := 0;
  v_done uuid[];
  v_p uuid;
  o record;
BEGIN
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  -- Lock every session whose goal is reached; an overlapping run skips them.
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT a.id
    FROM active_checkin_sessions a
    LEFT JOIN workouts w ON w.id = a.workout_id
    WHERE COALESCE(w.workout_started_at, a.started_at)
          + make_interval(mins => LEAST(GREATEST(COALESCE(w.planned_duration_minutes, a.planned_duration, 30), 15), 210))
          <= p_now
    ORDER BY a.started_at
    FOR UPDATE OF a SKIP LOCKED
  ) due;

  FOREACH v_sid IN ARRAY COALESCE(v_ids, '{}'::uuid[]) LOOP
    SELECT a.id, a.user_id, a.workout_id, a.goal_notified_at, a.reminder_notified_at,
           COALESCE(w.workout_started_at, a.started_at) AS start_at,
           LEAST(GREATEST(COALESCE(w.planned_duration_minutes, a.planned_duration, 30), 15), 210) AS goal,
           COALESCE(w.workout_type, a.workout_type, 'Workout') AS wtype,
           w.status AS w_status,
           (w.id IS NOT NULL AND (
              (a.user_id = w.user_id AND NOT COALESCE(w.creator_cancelled, false))
              OR (a.user_id = w.buddy_id AND NOT COALESCE(w.buddy_cancelled, false)))) AS in_workout
    INTO s
    FROM active_checkin_sessions a
    LEFT JOIN workouts w ON w.id = a.workout_id
    WHERE a.id = v_sid;
    CONTINUE WHEN NOT FOUND;  -- already credited with its workout partner

    -- Abandoned long before this job could see it: close, no push, no credit.
    IF s.start_at < p_now - interval '24 hours' THEN
      DELETE FROM active_checkin_sessions WHERE id = s.id;
      v_stale := v_stale + 1;
      CONTINUE;
    END IF;

    -- Before 3h30: push #1 at the goal, push #2 an hour later, never more.
    IF p_now < s.start_at + interval '210 minutes' THEN
      IF s.goal_notified_at IS NULL THEN
        UPDATE active_checkin_sessions SET goal_notified_at = p_now WHERE id = s.id;
        v_kind := 'goal';
        v_title := 'Workout complete';
        v_body := 'Workout complete. Log back into the app to confirm.';
      ELSIF s.reminder_notified_at IS NULL AND p_now >= s.goal_notified_at + interval '1 hour' THEN
        UPDATE active_checkin_sessions SET reminder_notified_at = p_now WHERE id = s.id;
        v_kind := 'reminder';
        v_title := 'Workout waiting';
        v_body := 'Your workout is still waiting. Open the app to confirm it.';
      ELSE
        CONTINUE;
      END IF;
      CONTINUE;
    END IF;

    -- 3h30: auto-complete. In a shared workout still in progress, credit
    -- everyone still in it first: closing the row fires
    -- cleanup_workout_sessions, which (as postgres) deletes all its sessions.
    v_close := s.in_workout AND s.w_status = 'in_progress';
    IF v_close THEN
      SELECT array_agg(a.id) INTO v_credit
      FROM active_checkin_sessions a
      JOIN workouts w ON w.id = a.workout_id
      WHERE a.workout_id = s.workout_id
        AND ((a.user_id = w.user_id AND NOT COALESCE(w.creator_cancelled, false))
          OR (a.user_id = w.buddy_id AND NOT COALESCE(w.buddy_cancelled, false)));
    ELSE
      v_credit := ARRAY[s.id];
    END IF;

    v_any := false;
    v_done := '{}';
    FOR c IN
      SELECT id, user_id, workout_emoji FROM active_checkin_sessions
      WHERE id = ANY(v_credit) ORDER BY id FOR UPDATE
    LOOP
      IF public._auto_credit(c.user_id, s.start_at, s.goal, s.wtype, c.workout_emoji) THEN
        v_any := true;
        v_paid := v_paid + 1;
      ELSE
        v_unpaid := v_unpaid + 1;
      END IF;
      v_done := v_done || c.user_id;
      DELETE FROM active_checkin_sessions WHERE id = c.id;
    END LOOP;

    -- M6b (owner rule 2026-10-02): a participant who confirmed ready and has
    -- not cancelled is in without a session too, unless already credited
    -- for their start day (e.g. a manual Finish credited them).
    IF v_close THEN
      FOR v_p IN
        SELECT x.u FROM workouts w2,
          LATERAL (VALUES (w2.user_id, w2.creator_ready AND NOT w2.creator_cancelled),
                          (w2.buddy_id, w2.buddy_ready AND NOT w2.buddy_cancelled)) AS x(u, ok)
        WHERE w2.id = s.workout_id AND x.u IS NOT NULL AND x.ok AND x.u <> ALL(v_done)
          AND NOT EXISTS (SELECT 1 FROM daily_team_checkins d
                          WHERE d.user_id = x.u
                            AND d.check_in_date = (s.start_at AT TIME ZONE public.safe_user_tz(x.u))::date)
      LOOP
        IF public._auto_credit(v_p, s.start_at, s.goal, s.wtype, NULL) THEN
          v_any := true;
          v_paid := v_paid + 1;
        ELSE
          v_unpaid := v_unpaid + 1;
        END IF;
      END LOOP;
    END IF;

    -- Close the shared row once: completed with the goal duration if anyone
    -- was paid, else (or over the daily cap) cancelled. Both flagged.
    IF v_close THEN
      BEGIN
        UPDATE workouts SET
          status = CASE WHEN v_any THEN 'completed' ELSE 'cancelled' END,
          actual_duration_minutes = CASE WHEN v_any THEN s.goal ELSE actual_duration_minutes END,
          workout_completed_at = CASE WHEN v_any THEN s.start_at + make_interval(mins => s.goal)
                                      ELSE workout_completed_at END,
          auto_completed = true,
          updated_at = p_now
        WHERE id = s.workout_id AND status = 'in_progress';
      EXCEPTION WHEN raise_exception THEN  -- daily_workout_limit_reached
        UPDATE workouts SET status = 'cancelled', auto_completed = true, updated_at = p_now
        WHERE id = s.workout_id AND status = 'in_progress';
      END;
    END IF;
  END LOOP;

  -- In-progress workouts nobody holds a session for, at 3h30: ready,
  -- not-cancelled participants are credited (M6b; started in the last 24h,
  -- not already credited for their start day), then the row is closed:
  -- completed if anyone was paid, else (or over the daily cap) cancelled.
  FOR o IN
    SELECT w.id, w.user_id, w.buddy_id, w.workout_started_at, w.workout_type,
           w.creator_ready AND NOT w.creator_cancelled AS creator_in,
           w.buddy_ready AND NOT w.buddy_cancelled AS buddy_in,
           LEAST(GREATEST(COALESCE(w.planned_duration_minutes, 30), 15), 210) AS goal
    FROM workouts w
    WHERE w.status = 'in_progress'
      AND w.workout_started_at <= p_now - interval '210 minutes'
      AND NOT EXISTS (SELECT 1 FROM active_checkin_sessions a WHERE a.workout_id = w.id)
    FOR UPDATE OF w SKIP LOCKED
  LOOP
    v_any := false;
    IF o.workout_started_at >= p_now - interval '24 hours' THEN
      FOR v_p IN
        SELECT x.u FROM (VALUES (o.user_id, o.creator_in), (o.buddy_id, o.buddy_in)) AS x(u, ok)
        WHERE x.u IS NOT NULL AND x.ok
          AND NOT EXISTS (SELECT 1 FROM daily_team_checkins d
                          WHERE d.user_id = x.u
                            AND d.check_in_date = (o.workout_started_at AT TIME ZONE public.safe_user_tz(x.u))::date)
      LOOP
        IF public._auto_credit(v_p, o.workout_started_at, o.goal, o.workout_type, NULL) THEN
          v_any := true;
          v_paid := v_paid + 1;
        ELSE
          v_unpaid := v_unpaid + 1;
        END IF;
      END LOOP;
    END IF;
    BEGIN
      UPDATE workouts SET
        status = CASE WHEN v_any THEN 'completed' ELSE 'cancelled' END,
        actual_duration_minutes = CASE WHEN v_any THEN o.goal ELSE actual_duration_minutes END,
        workout_completed_at = CASE WHEN v_any THEN o.workout_started_at + make_interval(mins => o.goal)
                                    ELSE workout_completed_at END,
        auto_completed = true,
        updated_at = p_now
      WHERE id = o.id AND status = 'in_progress';
    EXCEPTION WHEN raise_exception THEN  -- daily_workout_limit_reached
      UPDATE workouts SET status = 'cancelled', auto_completed = true, updated_at = p_now
      WHERE id = o.id AND status = 'in_progress';
    END;
    v_orphans := v_orphans + 1;
  END LOOP;

  RETURN jsonb_build_object('pushed', v_pushed, 'paid', v_paid, 'unpaid', v_unpaid,
                            'stale_closed', v_stale, 'orphans_closed', v_orphans);
END;
$function$

;
REVOKE EXECUTE ON FUNCTION public.process_stale_sessions(timestamp with time zone) FROM PUBLIC, anon, authenticated;
