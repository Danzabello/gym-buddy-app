-- M6 (DB audit DB-1, needs 20261116221000_tz_names_lookup): schedule_coach_max_today joins public.tz_names, a copy
-- of the same names, instead of pg_timezone_names. Only that join line changes in the function body.
CREATE OR REPLACE FUNCTION public.schedule_coach_max_today()
 RETURNS integer
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  WITH ins AS (
    INSERT INTO public.coach_max_schedule (user_id, scheduled_date, scheduled_time, has_checked_in)
    SELECT c.user_id, c.local_date,
           make_time((c.start_hour + c.minute_in_window / 60) % 24, c.minute_in_window % 60, 0),
           false
    FROM (
      SELECT up.id AS user_id,
             (now() AT TIME ZONE COALESCE(tz.name, 'Europe/Dublin'))::date AS local_date,
             w.start_hour,
             floor(random() * (w.end_hour - w.start_hour) * 60)::integer AS minute_in_window
      FROM public.user_profiles up
      LEFT JOIN public.tz_names tz ON tz.name = up.timezone
      LEFT JOIN public.notification_settings ns
             ON ns.user_id = up.id
            AND ns.quiet_hours_enabled
            AND ns.quiet_hours_start BETWEEN 0 AND 23
            AND ns.quiet_hours_end BETWEEN 0 AND 23
      CROSS JOIN LATERAL (
        SELECT COALESCE(ns.quiet_hours_end, 7) AS start_hour,
               CASE WHEN ns.user_id IS NULL THEN 17
                    WHEN ns.quiet_hours_start > ns.quiet_hours_end THEN ns.quiet_hours_start
                    ELSE ns.quiet_hours_start + 24 END AS end_hour
      ) w
      WHERE up.is_bot IS NOT TRUE
        AND EXISTS (SELECT 1 FROM public.team_members tm
                    JOIN public.buddy_teams bt ON bt.id = tm.team_id
                    WHERE tm.user_id = up.id AND bt.is_coach_max_team)
        AND NOT EXISTS (SELECT 1 FROM public.coach_max_schedule s
                        WHERE s.user_id = up.id
                          AND s.scheduled_date = (now() AT TIME ZONE COALESCE(tz.name, 'Europe/Dublin'))::date)
    ) c
    ON CONFLICT (user_id, scheduled_date) DO NOTHING
    RETURNING 1
  )
  SELECT count(*)::integer FROM ins;
$function$;

REVOKE EXECUTE ON FUNCTION public.schedule_coach_max_today() FROM PUBLIC, anon, authenticated;
