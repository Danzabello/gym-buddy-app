-- GROUP A (correction to 20260717164700): actually close the economy
-- write hole (LIVE-1).
--
-- The column-level REVOKEs in the previous migration were no-ops:
-- authenticated and anon hold a TABLE-level UPDATE+INSERT grant on
-- user_profiles (Supabase default, relacl 'arwdDxtm') that covers every
-- column. A column-level REVOKE cannot subtract from a table-level grant,
-- so has_column_privilege stayed true for xp/level/coin_balance/is_bot.
--
-- Correct pattern: drop the blanket table-level UPDATE/INSERT and re-grant
-- them on exactly the non-economy columns. The 4 economy columns then have
-- no client write privilege and are writable only by the SECURITY DEFINER
-- award_xp/award_coins functions (which run as owner). anon gets no
-- re-grant: every RLS write policy on user_profiles requires auth.uid(),
-- so anon has no legitimate write path.

REVOKE UPDATE, INSERT ON public.user_profiles FROM authenticated, anon;

-- Note: id is intentionally omitted from UPDATE (no legitimate client path
-- updates the primary key) but kept in INSERT (onboarding sets it).
GRANT UPDATE (
  display_name, age, gender, fitness_goals, workout_days_per_week,
  fitness_level, preferred_workout_time, looking_for_buddy, created_at,
  updated_at, last_check_in_date, current_weekly_goal, rest_tokens_available,
  weekly_commitment_active, avatar_id, onboarding_completed,
  preferred_streak_sort, custom_streak_order, username,
  workout_join_popups_enabled, avatar_border, preferred_workout_style, timezone
) ON public.user_profiles TO authenticated;

GRANT INSERT (
  id, display_name, age, gender, fitness_goals, workout_days_per_week,
  fitness_level, preferred_workout_time, looking_for_buddy, created_at,
  updated_at, last_check_in_date, current_weekly_goal, rest_tokens_available,
  weekly_commitment_active, avatar_id, onboarding_completed,
  preferred_streak_sort, custom_streak_order, username,
  workout_join_popups_enabled, avatar_border, preferred_workout_style, timezone
) ON public.user_profiles TO authenticated;
