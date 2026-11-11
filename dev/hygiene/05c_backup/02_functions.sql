-- Functions to restore (definitions as captured). ACL note: original ACL was PUBLIC+anon+authenticated+service_role on the first three;
-- notify_* were revoked from PUBLIC/anon/authenticated by 05a/05a2, so the rollback of 05c re-applies the grants below.
-- notify_workout_invite() acl at capture: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_workout_invite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_sender_name TEXT; v_service_key TEXT;
BEGIN
  SELECT COALESCE(display_name, username, 'Your buddy') INTO v_sender_name FROM user_profiles WHERE id = NEW.sender_id;
  SELECT decrypted_secret INTO v_service_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_service_key),
    body := json_build_object('user_id', NEW.recipient_id, 'title', '🏋️ Workout Invite!', 'body', v_sender_name || ' invited you to a workout!', 'type', 'workout_invite', 'reference_id', NEW.id::text)::jsonb);
  RETURN NEW;
END; $function$
;
-- notify_workout_invite_response() acl at capture: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_workout_invite_response()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_recipient_name TEXT; v_service_key TEXT;
BEGIN
  IF NEW.status IN ('accepted', 'declined') AND OLD.status = 'pending' THEN
    SELECT COALESCE(display_name, username, 'Your buddy') INTO v_recipient_name FROM user_profiles WHERE id = NEW.recipient_id;
    SELECT decrypted_secret INTO v_service_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    PERFORM net.http_post(
      url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_service_key),
      body := json_build_object('user_id', NEW.sender_id,
        'title', CASE WHEN NEW.status='accepted' THEN '✅ Workout Accepted!' ELSE '❌ Workout Declined' END,
        'body', CASE WHEN NEW.status='accepted' THEN v_recipient_name || ' is joining your workout!' ELSE v_recipient_name || ' can''t make the workout.' END,
        'type', CASE WHEN NEW.status='accepted' THEN 'workout_accepted' ELSE 'workout_declined' END,
        'reference_id', NEW.id::text)::jsonb);
  END IF;
  RETURN NEW;
END; $function$
;
-- is_user_in_active_workout(check_user_id uuid) acl at capture: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_user_in_active_workout(check_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  has_active BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM workouts w
    WHERE w.status = 'in_progress'
    AND (
      -- User started this workout
      (w.started_by_user_id = check_user_id)
      OR
      -- User is creator and has joined
      (w.user_id = check_user_id AND w.creator_joined = TRUE)
      OR
      -- User has an active check-in session
      EXISTS (
        SELECT 1 FROM active_checkin_sessions acs
        WHERE acs.user_id = check_user_id
        AND acs.linked_workout_id = w.id
      )
    )
  ) INTO has_active;
  
  RETURN has_active;
END;
$function$
;
-- get_workouts_awaiting_creator_join(creator_id uuid) acl at capture: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_workouts_awaiting_creator_join(creator_id uuid)
 RETURNS TABLE(workout_id uuid, workout_type text, buddy_name text, planned_duration_minutes integer, started_at timestamp with time zone, join_window_end timestamp with time zone, time_remaining_seconds integer, popup_already_shown boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    w.id as workout_id,
    w.workout_type,
    up.display_name as buddy_name,
    w.planned_duration_minutes,
    w.workout_started_at as started_at,
    -- Join window = started_at + (planned_duration / 4)
    w.workout_started_at + (w.planned_duration_minutes * INTERVAL '1 minute' / 4) as join_window_end,
    -- Time remaining in seconds
    EXTRACT(EPOCH FROM (
      (w.workout_started_at + (w.planned_duration_minutes * INTERVAL '1 minute' / 4)) - NOW()
    ))::INTEGER as time_remaining_seconds,
    COALESCE(w.creator_popup_shown, FALSE) as popup_already_shown
  FROM workouts w
  LEFT JOIN user_profiles up ON up.id = w.buddy_id
  WHERE w.user_id = creator_id
    AND creator_id = auth.uid()  -- caller's own workouts only
    AND w.status = 'in_progress'
    AND w.started_by_user_id = w.buddy_id  -- Buddy started it
    AND (w.creator_joined IS NULL OR w.creator_joined = FALSE)  -- Creator hasn't joined
    AND w.workout_started_at IS NOT NULL;
END;
$function$
;
