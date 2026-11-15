-- P-5, file 1 of 2: a server job that gives every Coach Max user today's coach_max_schedule row.
-- Prepared 2026-11-14 (data-layer pass). Applied 2026-11-15 with the owner's go-ahead for this file only: file 2
-- (the INSERT revoke) is not applied.
-- Design: dev/audits/p5_design.md. Additive only: one new function and one pg_cron job. No grant, policy or existing
-- object changes, so it is safe on its own and can run next to the client insert and the coach-max-cron Edge
-- Function: the UNIQUE (user_id, scheduled_date) key makes whichever writer comes second a no-op.
--
-- Who gets a row: a user_profiles row that is not a bot and is a member of a team with is_coach_max_team (the rule
-- the Edge Function's Part 1 uses, plus the explicit bot test). A deleted profile has no team_members row (FK
-- cascade), so it cannot be picked.
-- Which day: the user's own local today, from user_profiles.timezone (NOT NULL, validated by
-- trg_validate_user_timezone), the same column safe_user_tz and the Edge Function read. A value that is not a
-- zone name Postgres knows is read as Europe/Dublin (the fallback safe_user_tz uses) instead of raising, so one
-- bad row cannot stop the job for everyone (review gate 2, finding 3).
-- Users who already have today's row are left out before the insert; ON CONFLICT stays for a race with another
-- writer (review gate 2, finding 5).
-- Known and accepted: if a profile is deleted in the instant between this statement reading it and inserting its
-- row, the foreign key fails the whole run; the next run, 5 minutes later, is clean (finding 4).
-- service_role keeps EXECUTE through its default privilege, as for the other service-only helpers (finding 6).
-- Which time: copied from the Edge Function's _generateActiveWindowTime. 07:00 to 17:00 local; with quiet hours on
-- (both hours 0 to 23), from the end of quiet hours to their start, wrapping past midnight when quiet hours do not.
-- Returns the number of rows it inserted.
-- Not on a credit path: it takes none of the L0 to L4 locks and writes coach_max_schedule only (an L5 write).
-- Called by pg_cron as postgres. No client may call it.
-- Rollback: dev/rollback_20261115142635.sql (rehearsed before the apply: run twice inside a transaction that aborts).

CREATE FUNCTION public.schedule_coach_max_today()
RETURNS integer
LANGUAGE sql
SET search_path = public
AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION public.schedule_coach_max_today() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('coach-max-schedule-rows', '*/5 * * * *', 'SELECT public.schedule_coach_max_today();');
