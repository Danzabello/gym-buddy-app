-- Fix the 4 notify_* trigger functions that authenticated to send-notification
-- with a HARDCODED anon JWT. send-notification does getUser(bearer); the anon
-- key has no user, so those calls were rejected 401 unauthorized -- meaning
-- friend-request, friend-accepted, workout-invite and workout-invite-response
-- notifications had been silently failing at the auth layer (separate from,
-- and not fixed by, the FCM key fix -- they never reached FCM).
--
-- Fix: use the same Vault service-role pattern the other 2 notify_* triggers
-- already use (notify_buddy_checkin / notify_streak_update, from
-- 20260627155120_fix_notification_triggers_use_service_role) -- read
-- service_role_key from vault.decrypted_secrets and send it as the bearer.
-- Only the auth line changes in each function; payload/type/logic unchanged.
--
-- Verified on live 2026-07-22: after applying, fired one real instance of each
-- of the 4 triggers; net._http_response returned status_code 200 for all four
-- (vs 401 before). Also removes the hardcoded anon JWT from these bodies,
-- aligning them with the project's vault.decrypted_secrets convention.
--
-- Supersedes the pre-VC (anon-key, redacted) definitions of these 4 functions
-- captured in docs/pre_vc_schema_baseline_20260720.sql.

CREATE OR REPLACE FUNCTION public.notify_friend_request()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $f$
DECLARE
  v_requester_name TEXT;
  v_service_key TEXT;
BEGIN
  SELECT COALESCE(display_name, username, 'Someone') INTO v_requester_name
  FROM user_profiles WHERE id = NEW.user_id;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := json_build_object(
      'user_id', NEW.friend_id,
      'title', '👋 New Friend Request!',
      'body', v_requester_name || ' wants to be your gym buddy!',
      'type', 'friend_request',
      'reference_id', NEW.id::text
    )::jsonb
  );
  RETURN NEW;
END;
$f$;

CREATE OR REPLACE FUNCTION public.notify_friend_accepted()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $f$
DECLARE
  v_accepter_name TEXT;
  v_service_key TEXT;
BEGIN
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    SELECT COALESCE(display_name, username, 'Your friend') INTO v_accepter_name
    FROM user_profiles WHERE id = NEW.friend_id;

    SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    PERFORM net.http_post(
      url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_key
      ),
      body := json_build_object(
        'user_id', NEW.user_id,
        'title', '🎉 Friend Request Accepted!',
        'body', v_accepter_name || ' is now your gym buddy!',
        'type', 'friend_accepted',
        'reference_id', NEW.id::text
      )::jsonb
    );
  END IF;
  RETURN NEW;
END;
$f$;

CREATE OR REPLACE FUNCTION public.notify_workout_invite()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $f$
DECLARE
  v_sender_name TEXT;
  v_service_key TEXT;
BEGIN
  SELECT COALESCE(display_name, username, 'Your buddy') INTO v_sender_name
  FROM user_profiles WHERE id = NEW.sender_id;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := json_build_object(
      'user_id', NEW.recipient_id,
      'title', '🏋️ Workout Invite!',
      'body', v_sender_name || ' invited you to a workout!',
      'type', 'workout_invite',
      'reference_id', NEW.id::text
    )::jsonb
  );
  RETURN NEW;
END;
$f$;

CREATE OR REPLACE FUNCTION public.notify_workout_invite_response()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $f$
DECLARE
  v_recipient_name TEXT;
  v_service_key TEXT;
BEGIN
  IF NEW.status IN ('accepted', 'declined') AND OLD.status = 'pending' THEN
    SELECT COALESCE(display_name, username, 'Your buddy') INTO v_recipient_name
    FROM user_profiles WHERE id = NEW.recipient_id;

    SELECT decrypted_secret INTO v_service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    PERFORM net.http_post(
      url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_key
      ),
      body := json_build_object(
        'user_id', NEW.sender_id,
        'title', CASE WHEN NEW.status = 'accepted' THEN '✅ Workout Accepted!' ELSE '❌ Workout Declined' END,
        'body', CASE WHEN NEW.status = 'accepted'
          THEN v_recipient_name || ' is joining your workout!'
          ELSE v_recipient_name || ' can''t make the workout.' END,
        'type', CASE WHEN NEW.status = 'accepted' THEN 'workout_accepted' ELSE 'workout_declined' END,
        'reference_id', NEW.id::text
      )::jsonb
    );
  END IF;
  RETURN NEW;
END;
$f$;
