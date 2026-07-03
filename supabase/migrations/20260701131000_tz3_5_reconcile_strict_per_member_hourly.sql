-- STEP 3, migration #5 of the per-user timezone rework (Option B).
--
-- reconcile_stale_streaks becomes the SINGLE place a streak lapses to 0
-- (recompute_team_streak never resets for absence — tz3_3), judged STRICTLY
-- per member in each member's OWN timezone:
--
--   Reset iff there exists a human member m and a label L with
--     last_workout_date < L <= m_yesterday
--   where m_yesterday = (now() AT TIME ZONE safe_user_tz(m))::date - 1 and
--   m has neither a check-in for L nor an uncancelled break for L.
--
-- Key properties:
--   * A member still inside label L (their local today == L) is NOT judged
--     for L yet — they have until their own local midnight. The eastern
--     member of an offset pair simply reaches the verdict earlier.
--   * ALL labels in (last_workout_date, m_yesterday] are scanned per member,
--     not just last+1: a member can be break-covered on last+1 (day never
--     completed because the partner missed) and then genuinely miss last+2.
--   * A member who checked in is never the trigger; the absent partner is —
--     STRICT means either member's definitive miss breaks the shared streak.
--   * Coach Max is excluded from the member set (unchanged).
--   * The outer scan widens from last < utc_yesterday to last < utc_today:
--     since m_yesterday <= utc_today for every timezone (max UTC+14), any
--     potentially-lapsed streak satisfies last < utc_today.
--   * Memberless active streaks are skipped without reset (matches current
--     effective behavior).
--   * Reset still only zeroes current_streak (last_workout_date, longest and
--     best are untouched, preserving recompute's revive semantics).
--
-- Also moves the job from daily (00:10 UTC) to HOURLY so each member's local
-- midnight is caught within the hour. The function is idempotent, so hourly
-- runs are safe.

CREATE OR REPLACE FUNCTION public.reconcile_stale_streaks()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_streak record;
  v_utc_today date := (now() AT TIME ZONE 'utc')::date;
  v_member_ids uuid[];
  v_member uuid;
  v_m_yesterday date;
  v_broken boolean;
  v_reset_count integer := 0;
BEGIN
  FOR v_streak IN
    SELECT id, team_id, current_streak, last_workout_date
    FROM team_streaks
    WHERE is_active = true AND current_streak > 0
      AND (last_workout_date IS NULL OR last_workout_date < v_utc_today)
  LOOP
    SELECT array_agg(user_id) INTO v_member_ids
    FROM team_members
    WHERE team_id = v_streak.team_id
      AND user_id <> '00000000-0000-0000-0000-000000000001';

    IF v_streak.last_workout_date IS NULL THEN
      -- Active streak count with no completed day on record: inconsistent,
      -- reset (unchanged from the current function).
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
      CONTINUE;
    END IF;

    IF v_member_ids IS NULL THEN
      CONTINUE; -- memberless: nothing to judge (matches current behavior)
    END IF;

    v_broken := false;

    FOREACH v_member IN ARRAY v_member_ids LOOP
      -- This member's own fully-elapsed yesterday.
      v_m_yesterday := (now() AT TIME ZONE public.safe_user_tz(v_member))::date - 1;

      IF v_streak.last_workout_date + 1 <= v_m_yesterday THEN
        IF EXISTS (
          SELECT 1
          FROM generate_series(
                 (v_streak.last_workout_date + 1)::timestamp,
                 v_m_yesterday::timestamp,
                 interval '1 day') AS g(day)
          WHERE NOT EXISTS (
              SELECT 1 FROM daily_team_checkins dtc
              WHERE dtc.team_streak_id = v_streak.id
                AND dtc.user_id = v_member
                AND dtc.check_in_date = g.day::date
            )
            AND NOT EXISTS (
              SELECT 1 FROM break_day_usage bdu
              WHERE bdu.user_id = v_member
                AND bdu.break_date = g.day::date
                AND bdu.cancelled_at IS NULL
            )
        ) THEN
          v_broken := true;
          EXIT; -- STRICT: one member's definitive miss is enough
        END IF;
      END IF;
    END LOOP;

    IF v_broken THEN
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('reset_count', v_reset_count);
END;
$function$;

-- ── Schedule: daily -> hourly ────────────────────────────────────────────
-- :05 keeps it clear of the coach-max hourly job at :00.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'reconcile-stale-streaks-daily') THEN
    PERFORM cron.unschedule('reconcile-stale-streaks-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'reconcile-stale-streaks-hourly',
  '5 * * * *',
  $$SELECT public.reconcile_stale_streaks();$$
);
