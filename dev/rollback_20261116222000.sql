-- Rollback for 20261116222000_coach_max_schedule_tz_names.sql: the live body of 2026-11-16 (md5
-- 3550c06e83f1ffa8c684a2b6dcfc7f9b, from 20261115142635), joining pg_timezone_names again. Safe to run twice.
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
      LEFT JOIN pg_catalog.pg_timezone_names tz ON tz.name = up.timezone
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
