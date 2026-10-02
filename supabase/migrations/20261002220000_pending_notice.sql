-- Streak events M5: the server picks the ONE full-screen notice per app open.
-- get_pending_notice() for auth.uid(), unseen and at most 7 days old:
--   1. two or more streak events -> kind 'many', items = all of them
--   2. exactly one 'own' event   -> kind 'own'
--   3. exactly one 'friend' event -> kind 'friend'
--   4. auto-completed workout_logs -> kind 'auto_completed', items = all
--   else kind null.
-- 'others' = unseen items of lower priority left for the quiet Home card.
-- Names returned are the caller's own teammates (already readable to them).
-- mark_notice_seen(p_ids) marks exactly the ids the client was shown, only
-- the caller's rows, so anything that arrived in between stays unseen.
CREATE OR REPLACE FUNCTION public.get_pending_notice()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
  v_events jsonb;
  v_n integer;
  v_auto jsonb;
  v_auto_n integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', e.id, 'kind', e.kind, 'lost_streak', e.lost_streak,
           'team_id', e.team_id, 'team_name', bt.team_name,
           'is_coach_max_team', bt.is_coach_max_team,
           'buddy_name', (SELECT string_agg(COALESCE(p.display_name, p.username, 'Your buddy'), ', ')
                          FROM team_members tm JOIN user_profiles p ON p.id = tm.user_id
                          WHERE tm.team_id = e.team_id AND tm.user_id <> v_uid
                            AND tm.user_id <> v_coach_max_id),
           'missed_name', (SELECT COALESCE(p.display_name, p.username)
                           FROM user_profiles p WHERE p.id = e.missed_user_id),
           'created_at', e.created_at)
           ORDER BY e.kind = 'friend', e.created_at DESC), '[]'::jsonb),
         count(*)
  INTO v_events, v_n
  FROM streak_events e
  JOIN buddy_teams bt ON bt.id = e.team_id
  WHERE e.user_id = v_uid AND e.seen_at IS NULL AND e.created_at >= now() - interval '7 days';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', l.id, 'workout_name', l.workout_name, 'workout_date', l.workout_date,
           'minutes', l.actual_duration_minutes) ORDER BY l.created_at DESC), '[]'::jsonb),
         count(*)
  INTO v_auto, v_auto_n
  FROM workout_logs l
  WHERE l.user_id = v_uid AND l.auto_completed AND l.auto_completed_notice_seen_at IS NULL
    AND l.created_at >= now() - interval '7 days';

  IF v_n >= 2 THEN
    RETURN jsonb_build_object('kind', 'many', 'items', v_events, 'others', v_auto_n);
  ELSIF v_n = 1 THEN
    RETURN jsonb_build_object('kind', v_events->0->>'kind', 'items', v_events, 'others', v_auto_n);
  ELSIF v_auto_n > 0 THEN
    RETURN jsonb_build_object('kind', 'auto_completed', 'items', v_auto, 'others', 0);
  END IF;
  RETURN jsonb_build_object('kind', NULL, 'items', '[]'::jsonb, 'others', 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notice_seen(p_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_events integer;
  v_logs integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  UPDATE streak_events SET seen_at = now()
  WHERE user_id = v_uid AND id = ANY(p_ids) AND seen_at IS NULL;
  GET DIAGNOSTICS v_events = ROW_COUNT;
  UPDATE workout_logs SET auto_completed_notice_seen_at = now()
  WHERE user_id = v_uid AND id = ANY(p_ids) AND auto_completed AND auto_completed_notice_seen_at IS NULL;
  GET DIAGNOSTICS v_logs = ROW_COUNT;
  RETURN v_events + v_logs;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_pending_notice() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_pending_notice() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_notice_seen(uuid[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_notice_seen(uuid[]) TO authenticated;
