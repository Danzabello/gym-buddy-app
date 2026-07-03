-- Fix 2b: drop the orphaned personal-streak columns on user_profiles.
--
-- These columns were only ever read/written by the Dart StreakService, which
-- has now been deleted. All real streak state lives in team_streaks; the
-- dashboard, achievements, and profile views read team_streaks exclusively.
--
-- Verified before dropping (against the live DB):
--   * no views, indexes, generated columns, or constraints depend on them;
--   * no triggers on user_profiles reference them;
--   * the only SECURITY DEFINER functions that mention a streak column
--     (_apply_checkin_rewards, get_user_streaks, fix_existing_team_checkins)
--     read/write current_streak / longest_streak / last_workout_date on
--     team_streaks, and touch user_profiles only for level / id joins;
--   * no remaining client write targets these columns.
--
-- IF NOT EXISTS keeps this idempotent / safe to re-run.

ALTER TABLE public.user_profiles
  DROP COLUMN IF EXISTS current_streak,
  DROP COLUMN IF EXISTS longest_streak,
  DROP COLUMN IF EXISTS last_workout_date;
