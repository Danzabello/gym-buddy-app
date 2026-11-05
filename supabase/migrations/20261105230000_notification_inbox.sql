-- NOTIF-INBOX option C (prompt 27). The home bell will list what the app told the user in the last 7 days (prompt 28):
-- the exact words of each push, plus the pushes quiet hours held back. notification_log stays the dedupe and
-- rate-limit log, written only after Firebase accepts, so it has no words and misses those pushes.
-- send-notification writes notification_inbox after its category and dedupe checks and before it stops for quiet
-- hours or a missing token. The write fails open: a push is delivered or held exactly as before.
-- _send_push: a user with no device token now gets the HTTP request, so that row can be written, and the function
-- still returns false for them (process_stale_sessions' pushed count does not change). Coach Max is skipped.
-- Rollback: docs/rollback_20261105230000.sql.

CREATE TABLE public.notification_inbox (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid        NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  notification_type text        NOT NULL,
  title             text        NOT NULL,
  body              text        NOT NULL,
  quiet             boolean     NOT NULL DEFAULT false,
  reference_id      text,
  batch_key         text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notification_inbox_user_created_idx ON public.notification_inbox (user_id, created_at DESC);

ALTER TABLE public.notification_inbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.notification_inbox FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.notification_inbox TO authenticated;
GRANT ALL ON TABLE public.notification_inbox TO service_role;
CREATE POLICY "Users read own inbox" ON public.notification_inbox
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
COMMENT ON TABLE public.notification_inbox IS 'What the app told each user in the last 7 days, one row per push, emoji stripped. quiet = held back by quiet hours, never sent. Written only by send-notification; purged daily by purge-notification-inbox.';

SELECT cron.schedule('purge-notification-inbox', '23 3 * * *',
  $$DELETE FROM public.notification_inbox WHERE created_at < now() - interval '7 days'$$);

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
  v_has_token boolean;
BEGIN
  -- Coach Max has no phone and reads no inbox. A user with no token still gets the request, so send-notification
  -- can record the inbox row; the return value stays false for them because nothing can be delivered.
  IF p_user IS NULL OR p_user = '00000000-0000-0000-0000-000000000001'::uuid THEN
    RETURN false;
  END IF;
  v_has_token := EXISTS (SELECT 1 FROM device_tokens WHERE user_id = p_user);
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
  RETURN v_has_token;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public._send_push(uuid, text, jsonb, text, text, text, text, text, boolean, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._send_push(uuid, text, jsonb, text, text, text, text, text, boolean, uuid) TO service_role;
