-- LIVE-15 fix (team_streaks): verify_achievement_progress reads
-- best_streak/current_streak as ground truth for streak achievements, and
-- these columns were directly client-UPDATE-able with no column guard --
-- any team member could set best_streak=100 and get a legitimate-looking
-- achievement payout. recompute_team_streak (SECURITY DEFINER, search_path
-- pinned) is the only legitimate writer of these columns; confirmed via
-- exhaustive grep that no remaining Dart code path writes them directly
-- (the two prior direct writers -- friend_service.dart's
-- _backfillTodaysCheckIns and team_streak_service.dart's _resetStreak --
-- were replaced/removed in the preceding two migrations of this fix).
--
-- NOTE: this migration alone did NOT work as intended -- see the immediately
-- following migration (fix_team_streaks_column_update_trap) for why and for
-- the actual fix. Kept here, unedited, as an honest record of what was
-- literally applied and verified live to be a no-op (the table-level-grant
-- trap), rather than silently rewritten after the fact.
REVOKE UPDATE (current_streak, longest_streak, total_workouts, best_streak,
  last_workout_date, last_interaction_at)
ON public.team_streaks FROM authenticated, anon;
