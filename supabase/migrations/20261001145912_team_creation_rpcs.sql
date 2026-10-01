-- LIVE-23 / LIVE-25 (M1, additive): server-side team creation. The client
-- inserted buddy_teams / team_members / team_streaks directly
-- (friend_service._createTeamStreakAndGetIds, CoachMaxService.
-- initializeCoachMaxForUser); M2 revokes that. These two RPCs reproduce
-- exactly what those client paths wrote, but only for an ACCEPTED friendship
-- or the caller's own Coach Max team, and take no client-supplied
-- created_by, member list or streak values.

CREATE OR REPLACE FUNCTION public.create_buddy_team(p_friend_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_team_id uuid;
  v_streak_id uuid;
  v_caller_name text;
  v_friend_name text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  IF p_friend_id IS NULL OR p_friend_id = v_caller THEN
    RAISE EXCEPTION 'invalid_friend_id';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE status = 'accepted'
      AND ((user_id = v_caller AND friend_id = p_friend_id)
        OR (user_id = p_friend_id AND friend_id = v_caller))
  ) THEN
    RAISE EXCEPTION 'not_friends';
  END IF;

  -- Serialise concurrent calls for the same pair (double tap, both users
  -- accepting at once) so the lookup below cannot race into two teams.
  PERFORM pg_advisory_xact_lock(hashtext(LEAST(v_caller, p_friend_id)::text || GREATEST(v_caller, p_friend_id)::text));

  -- Same shared-team lookup as create_invite_team, minus Coach Max teams.
  SELECT tm1.team_id INTO v_team_id
  FROM team_members tm1
  JOIN team_members tm2 ON tm2.team_id = tm1.team_id AND tm2.user_id = p_friend_id
  JOIN buddy_teams bt ON bt.id = tm1.team_id AND bt.is_coach_max_team = false
  WHERE tm1.user_id = v_caller
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    SELECT id INTO v_streak_id FROM team_streaks WHERE team_id = v_team_id AND is_active = true;
    RETURN jsonb_build_object('team_id', v_team_id, 'streak_id', v_streak_id, 'created', false);
  END IF;

  SELECT display_name INTO v_caller_name FROM user_profiles WHERE id = v_caller;
  SELECT display_name INTO v_friend_name FROM user_profiles WHERE id = p_friend_id;
  IF v_caller_name IS NULL OR v_friend_name IS NULL THEN
    RAISE EXCEPTION 'missing_display_name';
  END IF;

  INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by)
  VALUES (v_caller_name || ' & ' || v_friend_name, '💪', false, 2, v_caller)
  RETURNING id INTO v_team_id;

  INSERT INTO team_members (team_id, user_id, role)
  VALUES (v_team_id, v_caller, 'member'), (v_team_id, p_friend_id, 'member');

  INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active)
  VALUES (v_team_id, 0, 0, true)
  RETURNING id INTO v_streak_id;

  RETURN jsonb_build_object('team_id', v_team_id, 'streak_id', v_streak_id, 'created', true);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_buddy_team(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_buddy_team(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.ensure_coach_max_team()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_coach_id uuid;
  v_team_id uuid;
  v_streak_id uuid;
  v_created boolean := false;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT id INTO v_coach_id FROM user_profiles
  WHERE is_bot = true AND id = '00000000-0000-0000-0000-000000000001';
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'coach_max_missing';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('coach_max_team:' || v_caller::text));

  SELECT tm.team_id INTO v_team_id
  FROM team_members tm
  JOIN buddy_teams bt ON bt.id = tm.team_id AND bt.is_coach_max_team = true
  WHERE tm.user_id = v_caller
  LIMIT 1;

  IF v_team_id IS NULL THEN
    INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by)
    VALUES ('Coach Max', '🤖', true, 2, v_caller)
    RETURNING id INTO v_team_id;

    INSERT INTO team_members (team_id, user_id, role)
    VALUES (v_team_id, v_caller, 'owner'), (v_team_id, v_coach_id, 'coach_max');

    v_created := true;
  END IF;

  SELECT id INTO v_streak_id FROM team_streaks WHERE team_id = v_team_id AND is_active = true;
  IF v_streak_id IS NULL THEN
    INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active)
    VALUES (v_team_id, 0, 0, true)
    RETURNING id INTO v_streak_id;
  END IF;

  RETURN jsonb_build_object('team_id', v_team_id, 'streak_id', v_streak_id, 'created', v_created);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.ensure_coach_max_team() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ensure_coach_max_team() TO authenticated;
