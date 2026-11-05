-- ROLLBACK for supabase/migrations/20261105230000_notification_inbox.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores _send_push (md5 of pg_get_functiondef 494338d98a90bdfb3a0374aadfb0d7dd, as of 20261008200000), unschedules
-- purge-notification-inbox and drops notification_inbox with its sender_id column (its rows are lost). send-notification fails open, so it is
-- safe to run before or after redeploying the function. Run as postgres.
BEGIN;
CREATE OR REPLACE FUNCTION public._send_push(p_user uuid, p_key text, p_vars jsonb, p_kind text, p_channel text, p_type text, p_ref text, p_tag text, p_urgent boolean DEFAULT false, p_sender uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;
REVOKE EXECUTE ON FUNCTION public._send_push(uuid, text, jsonb, text, text, text, text, text, boolean, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._send_push(uuid, text, jsonb, text, text, text, text, text, boolean, uuid) TO service_role;
SELECT cron.unschedule('purge-notification-inbox');
DROP TABLE public.notification_inbox;
COMMIT;
