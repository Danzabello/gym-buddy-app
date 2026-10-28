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
$function$
