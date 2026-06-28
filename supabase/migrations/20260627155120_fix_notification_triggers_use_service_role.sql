-- Both notification triggers were hardcoding a stale anon JWT to call
-- send-notification. Tonight's S1 fix correctly rejects anon-key calls
-- (no user identity to authorize against), which silently broke buddy-
-- checked-in, streak-broken, and milestone notifications. Switch both
-- to the service-role key from Vault, same pattern as coach-max-cron's
-- own pg_cron job (the trusted-server-bypass S1 already accounts for).

CREATE OR REPLACE FUNCTION public.notify_buddy_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_other_user_id UUID;
  v_checker_name TEXT;
  v_team_id UUID;
  v_service_key TEXT;
BEGIN
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  SELECT team_id INTO v_team_id
  FROM team_streaks
  WHERE id = NEW.team_streak_id;

  IF v_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT tm.user_id INTO v_other_user_id
  FROM team_members tm
  WHERE tm.team_id = v_team_id
    AND tm.user_id != NEW.user_id
  LIMIT 1;

  IF v_other_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(display_name, username, 'Your buddy') INTO v_checker_name
  FROM user_profiles
  WHERE id = NEW.user_id;

  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := json_build_object(
      'user_id', v_other_user_id,
      'title', '💪 Buddy Checked In!',
      'body', v_checker_name || ' just checked in — your turn!',
      'type', 'buddy_checked_in',
      'reference_id', v_team_id::text,
      'batch_key', 'checkin_' || v_team_id::text || '_' || CURRENT_DATE::text
    )::jsonb
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_streak_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_other_user_id UUID;
  v_team_name TEXT;
  v_service_key TEXT;
BEGIN
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  SELECT tm.user_id INTO v_other_user_id
  FROM team_members tm
  WHERE tm.team_id = NEW.team_id
    AND tm.user_id != (
      SELECT user_id FROM team_members
      WHERE team_id = NEW.team_id
      LIMIT 1
    )
  LIMIT 1;

  SELECT team_name INTO v_team_name
  FROM buddy_teams WHERE id = NEW.team_id;

  IF NEW.current_streak = 0 AND OLD.current_streak > 0 THEN
    FOR v_other_user_id IN
      SELECT user_id FROM team_members WHERE team_id = NEW.team_id
    LOOP
      PERFORM net.http_post(
        url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key
        ),
        body := json_build_object(
          'user_id', v_other_user_id,
          'title', '💔 Streak Broken!',
          'body', 'Your ' || v_team_name || ' streak was reset. Start fresh today!',
          'type', 'streak_broken',
          'reference_id', NEW.id::text
        )::jsonb
      );
    END LOOP;

  ELSIF NEW.current_streak != OLD.current_streak AND
        NEW.current_streak IN (7, 14, 30, 50, 100) THEN
    FOR v_other_user_id IN
      SELECT user_id FROM team_members WHERE team_id = NEW.team_id
    LOOP
      PERFORM net.http_post(
        url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key
        ),
        body := json_build_object(
          'user_id', v_other_user_id,
          'title', '🎉 ' || NEW.current_streak || ' Day Milestone!',
          'body', 'You and ' || v_team_name || ' hit a ' || NEW.current_streak || ' day streak!',
          'type', 'streak_milestone',
          'reference_id', NEW.id::text
        )::jsonb
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;
